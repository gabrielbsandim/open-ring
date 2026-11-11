import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/heart/presentation/measure_screen.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';

const _timing = MeasureTiming(
  window: Duration(seconds: 3),
  connectTimeout: Duration(seconds: 2),
);

final _at = DateTime.utc(2026, 11, 10, 22, 5);

class _Rig {
  final driver = FakeRingDriver();
  final lock = InMemorySyncLock();
  final store = RecordingSpotStore();

  Future<void> pump(WidgetTester tester, {bool paired = true, Widget? app}) =>
      pumpScaled(
        tester,
        app ?? screenHost(const MeasureScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(
            paired: paired ? const PairedRing(deviceId: fakeRingId) : null,
            driver: driver,
            lock: lock,
            spotStore: store,
            timing: _timing,
            clock: () => _at,
          ),
        ],
      );

  void emit(int value, {LiveKind kind = LiveKind.heartRate}) =>
      driver.emitLive(LiveReading(kind: kind, value: value, at: _at));
}

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.byKey(MeasureKeys.start));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _seconds(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('idle shows both kinds and a start button', (tester) async {
    await _Rig().pump(tester);

    expect(find.text('Measure now'), findsOneWidget);
    expect(find.byKey(MeasureKeys.kind(LiveKind.heartRate)), findsOneWidget);
    expect(find.byKey(MeasureKeys.kind(LiveKind.spo2)), findsOneWidget);
    expect(find.text('Ready to measure'), findsOneWidget);
    expect(find.text('Takes 3 seconds. Breathe normally.'), findsOneWidget);
    expect(find.byKey(MeasureKeys.cancel), findsNothing);
  });

  testWidgets('the SpO2 tip follows the prototype copy', (tester) async {
    await _Rig().pump(tester);

    await tester.tap(find.byKey(MeasureKeys.kind(LiveKind.spo2)));
    await tester.pump();

    expect(find.text('Hand resting, below heart level.'), findsOneWidget);
  });

  testWidgets('a heart rate run saves the median and frees the ring', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);

    await _start(tester);
    expect(rig.driver.liveKind, LiveKind.heartRate);
    expect(rig.lock.holder, isNotNull);
    expect(find.text('Looking for a pulse'), findsOneWidget);
    expect(find.text('3 s'), findsOneWidget);
    expect(find.byKey(MeasureKeys.cancel), findsOneWidget);

    rig
      ..emit(80)
      ..emit(250)
      ..emit(70);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    rig.emit(74);
    await _seconds(tester, 3);
    await tester.pumpAndSettle();

    expect(find.byKey(MeasureKeys.result), findsOneWidget);
    expect(find.text('Heart rate: 74 bpm'), findsOneWidget);
    expect(find.textContaining('today '), findsOneWidget);
    expect(find.text('Saved · queued for Health Connect'), findsOneWidget);
    expect(find.text('Measure again'), findsOneWidget);
    expect(rig.store.saved.single.reading.value, 74);
    expect(rig.store.saved.single.deviceId, fakeRingId);
    expect(
      rig.driver.calls,
      containsAllInOrder(['connect', 'startLive', 'stopLive', 'disconnect']),
    );
    expect(rig.lock.holder, isNull);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MeasureScreen)),
    );
    expect(container.read(dataRevisionProvider), 1);
  });

  testWidgets('SpO2 measures the chosen kind', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);

    await tester.tap(find.byKey(MeasureKeys.kind(LiveKind.spo2)));
    await tester.pumpAndSettle();
    await _start(tester);
    rig.emit(97, kind: LiveKind.spo2);
    await _seconds(tester, 3);
    await tester.pumpAndSettle();

    expect(rig.driver.liveKind, LiveKind.spo2);
    expect(find.text('Blood oxygen: 97%'), findsOneWidget);
  });

  testWidgets('cancel stops the run and saves nothing', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);

    await _start(tester);
    rig.emit(72);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(MeasureKeys.cancel));
    await tester.pumpAndSettle();

    expect(find.byKey(MeasureKeys.cancelled), findsOneWidget);
    expect(
      find.text('Measurement cancelled. Nothing was saved.'),
      findsOneWidget,
    );
    expect(rig.store.saved, isEmpty);
    expect(rig.driver.calls, containsAllInOrder(['stopLive', 'disconnect']));
    expect(rig.lock.holder, isNull);
    await _seconds(tester, 4);
    expect(find.byKey(MeasureKeys.result), findsNothing);
  });

  testWidgets('no pulse in the window times out without saving', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);

    await _start(tester);
    await _seconds(tester, 3);
    await tester.pumpAndSettle();

    expect(find.byKey(MeasureKeys.failure), findsOneWidget);
    expect(find.textContaining('No pulse found in 3 s'), findsOneWidget);
    expect(rig.store.saved, isEmpty);
    expect(rig.lock.holder, isNull);
  });

  testWidgets('a ring that cannot be reached fails before reading', (
    tester,
  ) async {
    final rig = _Rig();
    rig.driver.connectError = StateError('GATT_ERROR 133');
    await rig.pump(tester);

    await _start(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the ring'), findsOneWidget);
    expect(rig.driver.calls, isNot(contains('startLive')));
    expect(rig.lock.holder, isNull);
  });

  testWidgets('a running sync keeps the ring busy', (tester) async {
    final rig = _Rig();
    rig.lock.holder = 'sync';
    await rig.pump(tester);

    await _start(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('busy with a sync'), findsOneWidget);
    expect(rig.driver.connects, 0);
    expect(rig.lock.holder, 'sync');
  });

  testWidgets('without a ring it points to the Ring tab', (tester) async {
    final rig = _Rig();
    await rig.pump(tester, paired: false);

    await _start(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('No ring paired'), findsOneWidget);
    expect(find.byKey(MeasureKeys.openRing), findsOneWidget);
    expect(rig.driver.connects, 0);
  });

  testWidgets('a failed save still shows the reading', (tester) async {
    final rig = _Rig();
    await pumpScaled(
      tester,
      screenHost(const MeasureScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(
          paired: const PairedRing(deviceId: fakeRingId),
          driver: rig.driver,
          spotStore: RecordingSpotStore(failure: Exception('disk full')),
          timing: _timing,
        ),
      ],
    );

    await _start(tester);
    rig.emit(66);
    await _seconds(tester, 3);
    await tester.pumpAndSettle();

    expect(find.text('Heart rate: 66 bpm'), findsOneWidget);
    expect(find.textContaining('could not be saved'), findsOneWidget);
  });

  testWidgets('Heart opens Measure now inside its tab', (tester) async {
    await _Rig().pump(tester, app: const OpenRingApp());

    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.heart)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(HeartScreen.measureKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HeartScreen.measureKey));
    await tester.pumpAndSettle();

    expect(find.byType(MeasureScreen), findsOneWidget);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });
}
