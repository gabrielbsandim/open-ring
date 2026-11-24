import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/infrastructure/drift_data_exporter.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_analysis_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';

import '../../../helpers/database.dart';

const _rawFixture = 'MEAL-RAW-FIXTURE-7b1e44';
const _itemFixture = 'Mealfixtureitem';
const _shaFixture = 'MEAL-SHA-FIXTURE-c90d12';
const _hostFixture = 'meals.example.com';
const _modelFixture = 'MEAL-MODEL-FIXTURE-3f8a';

String _text(String path) {
  final bytes = File(path).readAsBytesSync();
  if (!path.endsWith('.zip')) return utf8.decode(bytes);
  return [
    for (final entry in ZipDecoder().decodeBytes(bytes).files)
      utf8.decode(entry.content),
  ].join('\n');
}

void main() {
  for (final format in ExportFormat.values) {
    test(
      'a full ${format.name} export holds no meal analysis or item',
      () async {
        final at = DateTime.utc(2026, 6, 1, 12);
        final db = await pairedDatabase();
        final meal = await DriftMealStore(db).add(
          MealDraft(at: at, offsetMinutes: 0),
          now: at,
          photo: 'meal_1.jpg',
        );
        final store = DriftMealAnalysisStore(db);
        final row = await store.enqueue(meal.id, 'meal_1.jpg', (
          providerHost: _hostFixture,
          model: _modelFixture,
          promptVersion: 1,
          outputSchema: 2,
        ), now: at);
        await store.markSending(row.id, now: at);
        await store.complete(row.id, const (
          status: MealAnalysisStatus.done,
          sent: (sha256: _shaFixture, width: 768, height: 576, bytes: 1),
          rawText: _rawFixture,
          confidence: MealPhotoConfidence.medium,
          usage: null,
          cost: null,
          errorKind: null,
          suggestion: MealPhotoSuggestion(
            isFood: MealPhotoFlag.yes,
            kind: MealPhotoKind.main,
            protein: MealPhotoFlag.yes,
            caffeine: MealPhotoFlag.no,
            fried: MealPhotoFlag.no,
            sugaryDrink: MealPhotoFlag.no,
            veg: MealPhotoVeg.some,
            alcohol: MealPhotoAlcohol.none,
            processed: MealPhotoProcessed.notMostly,
            items: [
              MealPhotoItem(
                name: _itemFixture,
                measure: MealPhotoMeasure.bowl,
                countX2: 2,
                grams: 300,
              ),
            ],
          ),
        ), now: at);
        final root = Directory.systemTemp.createTempSync(
          'openring_meal_export_',
        );
        addTearDown(() => root.delete(recursive: true));

        final result =
            await DriftDataExporter(
              database: db,
              clock: () => DateTime.utc(2026, 11, 24),
              directory: () async => root,
            ).export(
              ExportRequest(
                from: DateTime.utc(2026),
                to: DateTime.utc(2026, 12),
                kinds: ExportKind.values,
                format: format,
              ),
            );

        final text = result.files.map((f) => _text(f.path)).join('\n');
        for (final fixture in [
          _rawFixture,
          _itemFixture,
          _shaFixture,
          _hostFixture,
          _modelFixture,
          'meal_analyses',
          'meal_items',
        ]) {
          expect(text, isNot(contains(fixture)));
        }
      },
    );
  }
}
