import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart' show LocalDate;
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/infrastructure/drift_data_exporter.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';
import 'package:open_ring/features/trajectory/infrastructure/drift_projection_store.dart';

import '../../helpers/database.dart';

const _trendFixture = 81.6173;
const _rateFixture = -0.4729;
const _lowFixture = 77.3141;
const _midFixture = 78.2718;
const _highFixture = 79.1618;
const _createdFixture = 1795597313579;

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
      'a full ${format.name} export holds no trajectory projection value',
      () async {
        final db = await pairedDatabase();
        await DriftProjectionStore(db).insertIfAbsent(
          TrajectoryProjection(
            monday: const LocalDate(2026, 11, 23),
            trendKg: _trendFixture,
            rateKgPerWeek: _rateFixture,
            lowKg: _lowFixture,
            midKg: _midFixture,
            highKg: _highFixture,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              _createdFixture,
              isUtc: true,
            ),
          ),
        );
        final root = Directory.systemTemp.createTempSync(
          'openring_traj_export_',
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
          '$_trendFixture',
          '$_rateFixture',
          '$_lowFixture',
          '$_midFixture',
          '$_highFixture',
          '$_createdFixture',
        ]) {
          expect(text, isNot(contains(fixture)));
        }
      },
    );
  }
}
