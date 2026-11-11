import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/health_sync/presentation/health_status_screen.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_cards.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/fake_health_writer.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

final class _Rig {
  new({
    MetricsScenario? scenario,
    List<SyncRun> runs = const [],
    AutoMeasurements measurements = AutoMeasurements.allOn,
    Set<RingCapability>? capabilities,
    this.outbox,
  }) : scenario = scenario ?? fullDataScenario,
       driver = FakeRingDriver(capabilities: capabilities),
       store = FakeSyncStore(
         ring: PairedRing(
           deviceId: fakeRingId,
           lastSyncAt: (scenario ?? fullDataScenario).ring.lastSyncAt,
           measurements: measurements,
         ),
         runs: [...runs],
       );

  final MetricsScenario scenario;
  final FakeRingDriver driver;
  final FakeSyncStore store;
  final OutboxSummary? outbox;
  final scheduler = FakeSyncScheduler();
  final battery = FakeBatterySettings();
  final lock = InMemorySyncLock();

  List<Override> get overrides => [
    ...metricsOverrides(
      scenario,
      ring: ringOverrides(
        store: store,
        scheduler: scheduler,
        batterySettings: battery,
        driver: driver,
        lock: lock,
        clock: () => metricsNow,
      ),
    ),
    healthWriterProvider.overrideWithValue(FakeHealthWriter()),
    outboxSummaryReaderProvider.overrideWithValue(
      FakeOutboxSummaryReader(outbox),
    ),
    healthSyncProvider.overrideWith(RecordingHealthSyncController.new),
  ];

  Future<void> pump(WidgetTester tester, {bool app = false}) => pumpScaled(
    tester,
    app ? const OpenRingApp() : screenHost(const RingScreen()),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    overrides: overrides,
  );
}

Future<void> _openRingTab(WidgetTester tester) async {
  await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _within(Key key, Finder matching) =>
    find.descendant(of: find.byKey(key), matching: matching);

void main() {
  group('sync log', () {
    testWidgets('lists each run with its outcome, time and detail', (
      tester,
    ) async {
      final rig = _Rig(
        runs: [
          SyncRun(
            at: metricsNow.subtract(const Duration(minutes: 20)),
            outcome: SyncRunOutcome.completed,
            kinds: const {RecordKind.heartRate, RecordKind.stress},
            recordCount: 46,
          ),
          SyncRun(
            at: metricsNow.subtract(const Duration(hours: 2)),
            outcome: SyncRunOutcome.unreachable,
          ),
          SyncRun(
            at: metricsNow.subtract(const Duration(hours: 3)),
            outcome: SyncRunOutcome.partial,
          ),
        ],
      );
      await rig.pump(tester);

      expect(_within(RingKeys.log, find.text('Recent syncs')), findsOneWidget);
      expect(_within(RingKeys.log, find.text('Synced')), findsOneWidget);
      expect(
        _within(RingKeys.log, find.text('46 records · heart rate, stress')),
        findsOneWidget,
      );
      expect(_within(RingKeys.log, find.text('Failed')), findsOneWidget);
      expect(
        _within(RingKeys.log, find.text('Ring out of range or out of battery')),
        findsOneWidget,
      );
      expect(_within(RingKeys.log, find.text('Partly synced')), findsOneWidget);
      expect(_within(RingKeys.log, find.text('No new data')), findsOneWidget);
      expect(find.byKey(RingKeys.logEmpty), findsNothing);
    });

    testWidgets('says so when nothing was logged yet', (tester) async {
      await _Rig().pump(tester);

      expect(find.byKey(RingKeys.logEmpty), findsOneWidget);
      expect(find.text('No syncs logged yet'), findsOneWidget);
    });

    testWidgets('a sync from the screen adds its run to the log', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);

      await _tap(tester, find.byKey(RingKeys.syncNow));

      expect(rig.store.runs, hasLength(1));
      expect(find.byKey(RingKeys.logEmpty), findsNothing);
      expect(_within(RingKeys.log, find.text('Synced')), findsOneWidget);
    });
  });

  group('automatic measurements', () {
    testWidgets('shows each measurement with its interval', (tester) async {
      await _Rig().pump(tester);

      final card = find.byKey(RingKeys.measurements);
      await tester.ensureVisible(card);
      expect(
        _within(
          RingKeys.measurements,
          find.text('Automatic measurements on the ring'),
        ),
        findsOneWidget,
      );
      for (final measurement in AutoMeasurement.values) {
        expect(find.byKey(RingKeys.measurement(measurement)), findsOneWidget);
      }
      expect(
        _within(
          RingKeys.measurement(AutoMeasurement.heartRate),
          find.text('Every 5 min'),
        ),
        findsOneWidget,
      );
      expect(
        _within(
          RingKeys.measurement(AutoMeasurement.stress),
          find.text('Every 30 min'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('turning one off saves the choice for the next sync', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);

      await _tap(tester, find.byKey(RingKeys.measurement(AutoMeasurement.hrv)));

      expect(
        rig.store.ring?.measurements,
        const AutoMeasurements(off: {AutoMeasurement.hrv}),
      );
      expect(
        _within(RingKeys.measurement(AutoMeasurement.hrv), find.text('Off')),
        findsOneWidget,
      );
    });

    testWidgets('heart rate off warns what it costs', (tester) async {
      await _Rig(
        measurements: const AutoMeasurements(off: {AutoMeasurement.heartRate}),
      ).pump(tester);

      await tester.ensureVisible(find.byKey(RingKeys.measurements));
      expect(
        find.text('Off. Resting heart rate and readiness need it.'),
        findsOneWidget,
      );
    });

    testWidgets('a ring without the settings shows no card', (tester) async {
      await _Rig(capabilities: {RingCapability.battery}).pump(tester);

      expect(find.byKey(RingKeys.measurements), findsNothing);
      expect(find.byKey(RingKeys.find), findsNothing);
      expect(find.byKey(RingKeys.unpair), findsOneWidget);
    });
  });

  group('health row', () {
    testWidgets('shows the connection and the send queue', (tester) async {
      await _Rig(
        outbox: OutboxSummary(
          pendingRecords: const {HealthRecordKind.heartRate: 12},
          pendingRows: 1,
        ),
      ).pump(tester);

      await tester.ensureVisible(find.byKey(RingKeys.health));
      expect(
        _within(RingKeys.health, find.text('Connected · 12 records waiting')),
        findsOneWidget,
      );
    });

    testWidgets('opens the health status screen', (tester) async {
      final rig = _Rig();
      await rig.pump(tester, app: true);
      await _openRingTab(tester);

      await _tap(tester, find.byKey(RingKeys.health));

      expect(find.byType(HealthStatusScreen), findsOneWidget);
    });
  });

  group('find ring', () {
    testWidgets('lights the ring and says for how long', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);

      await _tap(tester, find.byKey(RingKeys.find));

      expect(rig.driver.calls, ['connect', 'findDevice', 'disconnect']);
      expect(
        _within(
          RingKeys.findStatus,
          find.text("The ring's green light is on for 10 seconds."),
        ),
        findsOneWidget,
      );
    });

    testWidgets('waits for a running sync', (tester) async {
      final rig = _Rig();
      rig.lock.holder = 'background';
      await rig.pump(tester);

      await _tap(tester, find.byKey(RingKeys.find));

      expect(rig.driver.connects, 0);
      expect(
        find.text('A sync is running. Try again when it ends.'),
        findsOneWidget,
      );
    });

    testWidgets('a ring out of reach says so', (tester) async {
      final rig = _Rig();
      rig.driver.connectError = StateError('GATT_ERROR 133');
      await rig.pump(tester);

      await _tap(tester, find.byKey(RingKeys.find));

      expect(
        find.text('Could not reach the ring. Bring it close and try again.'),
        findsOneWidget,
      );
    });
  });

  group('unpair', () {
    testWidgets('clears the ring, stops background sync and opens pairing', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester, app: true);
      await _openRingTab(tester);

      await _tap(tester, find.byKey(RingKeys.unpair));
      expect(find.text('Unpair R09_C0FE?'), findsOneWidget);
      expect(find.textContaining('Data already saved stays'), findsOneWidget);
      await tester.tap(find.byKey(RingKeys.unpairConfirm));
      await tester.pumpAndSettle();

      expect(rig.store.forgotten, [fakeRingId]);
      expect(rig.store.ring, isNull);
      expect(rig.scheduler.cancels, 1);
      expect(find.byType(PairScreen), findsOneWidget);
    });

    testWidgets('cancel keeps the ring paired', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);

      await _tap(tester, find.byKey(RingKeys.unpair));
      await tester.tap(find.byKey(RingKeys.unpairCancel));
      await tester.pumpAndSettle();

      expect(rig.store.forgotten, isEmpty);
      expect(rig.scheduler.cancels, 0);
      expect(find.byType(RingScreen), findsOneWidget);
    });

    testWidgets('a failed unpair stays and says so', (tester) async {
      final rig = _Rig();
      rig.store.forgetError = Exception('disk full');
      await rig.pump(tester, app: true);
      await _openRingTab(tester);

      await _tap(tester, find.byKey(RingKeys.unpair));
      await tester.tap(find.byKey(RingKeys.unpairConfirm));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not unpair the ring. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(PairScreen), findsNothing);
      expect(rig.scheduler.cancels, 0);
    });
  });

  group('offline ring', () {
    testWidgets('opens the Android battery settings', (tester) async {
      final rig = _Rig(scenario: offlineScenario);
      await rig.pump(tester);

      await _tap(tester, find.byKey(RingKeys.batterySettings));

      expect(rig.battery.opened, 1);
      expect(find.text('Open Android battery settings'), findsOneWidget);
    });

    testWidgets('search again starts a sync', (tester) async {
      final rig = _Rig(scenario: offlineScenario);
      await rig.pump(tester);

      expect(find.text('Search again'), findsOneWidget);
      await _tap(tester, find.byKey(RingKeys.searchAgain));

      expect(rig.driver.connects, 1);
    });
  });
}
