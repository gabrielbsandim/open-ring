import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/drift_ai_report_store.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_config_store.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/infrastructure/drift_data_exporter.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';

const _keyFixture = 'sk-test-FIXTURE-9f3c2a7d';
const _reportFixture = 'AI-REPORT-FIXTURE-41c8e0';

String _text(String path) {
  final bytes = File(path).readAsBytesSync();
  if (!path.endsWith('.zip')) return utf8.decode(bytes);
  return [
    for (final entry in ZipDecoder().decodeBytes(bytes).files)
      utf8.decode(entry.content),
  ].join('\n');
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final format in ExportFormat.values) {
    test(
      'a full ${format.name} export holds no AI key, ai_ setting or report',
      () async {
        final secrets = InMemorySecretStore();
        await secrets.write(aiApiKeySecretName, _keyFixture);
        await SharedPreferencesAiConfigStore().writeConfig(
          const AiConfig(
            baseUrl: 'https://api.example.com/v1',
            model: 'model-x',
            keyLastFour: '2a7d',
          ),
        );
        final db = await pairedDatabase();
        await DriftAiReportStore(db).insert(
          sampleAiReport(at: DateTime.utc(2026, 6), text: _reportFixture),
        );
        final root = Directory.systemTemp.createTempSync('openring_ai_export_');
        addTearDown(() => root.delete(recursive: true));

        final result =
            await DriftDataExporter(
              database: db,
              clock: () => DateTime.utc(2026, 11, 23),
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
        expect(text, isNot(contains(_keyFixture)));
        expect(text, isNot(contains('api.example.com')));
        expect(text, isNot(contains(_reportFixture)));
        expect(text, isNot(contains('reports.example.com')));
        for (final key in SharedPreferencesAiConfigStore.keys) {
          expect(text, isNot(contains(key)));
        }
      },
    );
  }
}
