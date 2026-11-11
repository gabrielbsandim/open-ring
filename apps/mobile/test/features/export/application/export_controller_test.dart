import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';

import '../../../helpers/settings_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 10, 9);

  test('ranges end just after now and start where the choice says', () {
    final month = exportRequestFor(ExportState(), now);
    final week = exportRequestFor(ExportState(range: ExportRange.week), now);
    final all = exportRequestFor(ExportState(range: ExportRange.all), now);

    expect(month.to, now.add(const Duration(milliseconds: 1)));
    expect(month.from, now.subtract(const Duration(days: 30)));
    expect(week.from, now.subtract(const Duration(days: 7)));
    expect(all.from.millisecondsSinceEpoch, 0);
    expect(month.kinds, ExportKind.values.toSet());
    expect(month.format, ExportFormat.csv);
  });

  test('the file name drops the folder', () {
    expect(
      exportFileName(
        const ExportFile(path: '/tmp/a/openring-x.csv', mimeType: 'text/csv'),
      ),
      'openring-x.csv',
    );
  });

  test('changing an option after a run clears the result', () {
    final done = ExportState().completed(sampleExportResult());

    final changed = done.withOptions(format: ExportFormat.json);

    expect(changed.phase, ExportPhase.idle);
    expect(changed.result, isNull);
    expect(changed.format, ExportFormat.json);
  });

  test('options stay fixed while an export runs', () {
    final running = ExportState().started();

    expect(running.withOptions(range: ExportRange.all), same(running));
    expect(running.canRun, isFalse);
  });

  test('run then share hands the written files to the sharer', () async {
    final sharer = FakeFileSharer();
    final container = ProviderContainer(
      overrides: settingsOverrides(sharer: sharer),
    );
    addTearDown(container.dispose);
    final export = container.read(exportProvider.notifier);

    await export.run();
    await export.share();

    final state = container.read(exportProvider);
    expect(state.phase, ExportPhase.done);
    expect(state.result?.recordCount, 13152);
    expect(sharer.shared.single, state.result?.files);
    expect(state.shareFailed, isFalse);
  });
}
