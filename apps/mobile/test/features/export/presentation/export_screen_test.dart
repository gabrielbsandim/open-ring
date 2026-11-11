import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/presentation/export_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/settings_fakes.dart';

final _states = <String, ExportState>{
  'idle': ExportState(),
  'running': ExportState().started(),
  'done': ExportState().completed(sampleExportResult()),
  'done with a failed share': ExportState()
      .completed(sampleExportResult())
      .sharing(failed: true),
  'failed': ExportState().failed(),
  'without a data type': ExportState(kinds: const {}),
};

Future<void> _pump(WidgetTester tester, List<Override> overrides) => pumpScaled(
  tester,
  screenHost(const ExportScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: overrides,
);

Future<void> _tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pump();
}

ExportState _state(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ExportScreen)))
        .read(exportProvider);

void main() {
  for (final MapEntry(key: name, value: state) in _states.entries) {
    group('Export $name', () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpScaled(
            tester,
            screenHost(const ExportScreen()),
            textScaler: c.textScaler,
            brightness: c.brightness,
            locale: c.locale,
            overrides: settingsOverrides(export: state),
          );

          await scrollThrough(tester);
          expect(find.byType(ExportScreen), findsOneWidget);
        });
      }
    });
  }

  testWidgets('exports the chosen range, kinds and format, then shares', (
    tester,
  ) async {
    final exporter = FakeDataExporter();
    final sharer = FakeFileSharer();
    await _pump(tester, settingsOverrides(exporter: exporter, sharer: sharer));

    await _tap(tester, ExportKeys.range(ExportRange.week));
    await _tap(tester, ExportKeys.kind(ExportKind.stress));
    await _tap(tester, ExportKeys.format(ExportFormat.json));
    await _tap(tester, ExportKeys.run);
    await tester.pumpAndSettle();

    final request = exporter.requests.single;
    expect(request.format, ExportFormat.json);
    expect(request.kinds, isNot(contains(ExportKind.stress)));
    expect(request.kinds, hasLength(ExportKind.values.length - 1));
    expect(request.from, settingsNow.subtract(const Duration(days: 7)));
    expect(request.to.isAfter(settingsNow), isTrue);

    await tester.scrollUntilVisible(
      find.byKey(ExportKeys.done),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('openring-20261110-090000.json'), findsOneWidget);
    expect(find.text('13,152 records'), findsOneWidget);
    expect(sharer.shared, isEmpty);

    await _tap(tester, ExportKeys.share);
    await tester.pumpAndSettle();

    expect(sharer.shared.single.single.path, endsWith('.json'));
    expect(find.byKey(ExportKeys.shareFailed), findsNothing);
  });

  testWidgets('shows the running state until the file is written', (
    tester,
  ) async {
    final hold = Completer<void>();
    await _pump(
      tester,
      settingsOverrides(exporter: FakeDataExporter(hold: hold)),
    );

    await _tap(tester, ExportKeys.run);

    expect(_state(tester).phase, ExportPhase.running);
    expect(find.text('Exporting…'), findsOneWidget);
    expect(find.byKey(ExportKeys.running), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(ExportKeys.run),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);

    hold.complete();
    await tester.pumpAndSettle();

    expect(_state(tester).phase, ExportPhase.done);
    expect(find.byKey(ExportKeys.running), findsNothing);
  });

  testWidgets('a failed export says so and shares nothing', (tester) async {
    final sharer = FakeFileSharer();
    await _pump(
      tester,
      settingsOverrides(exporter: FakeDataExporter(fail: true), sharer: sharer),
    );

    await _tap(tester, ExportKeys.run);
    await tester.pumpAndSettle();

    expect(_state(tester).phase, ExportPhase.failed);
    await tester.scrollUntilVisible(
      find.byKey(ExportKeys.failed),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(ExportKeys.share), findsNothing);
    expect(sharer.shared, isEmpty);
  });

  testWidgets('a share sheet that fails to open is reported', (tester) async {
    final sharer = FakeFileSharer()..fail = true;
    await _pump(tester, settingsOverrides(sharer: sharer));

    await _tap(tester, ExportKeys.run);
    await tester.pumpAndSettle();
    await _tap(tester, ExportKeys.share);
    await tester.pumpAndSettle();

    expect(find.byKey(ExportKeys.shareFailed), findsOneWidget);
  });

  testWidgets('without a data type the export cannot start', (tester) async {
    final exporter = FakeDataExporter();
    await _pump(tester, settingsOverrides(exporter: exporter));

    for (final kind in ExportKind.values) {
      await _tap(tester, ExportKeys.kind(kind));
    }

    expect(find.byKey(ExportKeys.noKind), findsOneWidget);
    await _tap(tester, ExportKeys.run);
    expect(exporter.requests, isEmpty);
  });

  testWidgets('reads the done state in German', (tester) async {
    await pumpScaled(
      tester,
      screenHost(const ExportScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.light,
      locale: const Locale('de'),
      overrides: settingsOverrides(
        export: ExportState().completed(sampleExportResult()),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(ExportKeys.done),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Datei bereit'), findsOneWidget);
    expect(find.text('13.152 Einträge'), findsOneWidget);
    expect(find.text('Teilen'), findsOneWidget);
  });
}
