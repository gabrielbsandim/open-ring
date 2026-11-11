import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:open_ring/features/heart/presentation/heart_labels.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/heart/presentation/measure_screen.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/presentation/first_sync_screen.dart';
import 'package:open_ring/features/onboarding/presentation/health_permission_screen.dart';
import 'package:open_ring/features/onboarding/presentation/permissions_screen.dart';
import 'package:open_ring/features/onboarding/presentation/profile_screen.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/ring/presentation/pair_error_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_cards.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/presentation/readiness_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:ring_driver/ring_driver.dart';

import '../helpers/ble_fakes.dart';
import '../helpers/layout_harness.dart';
import '../helpers/metrics_fakes.dart';
import '../helpers/onboarding_fakes.dart';
import '../helpers/ring_fakes.dart';

const screens = <String, Widget>{
  'Today': TodayScreen(),
  'Readiness': ReadinessScreen(),
  'Sleep': SleepScreen(),
  'Heart': HeartScreen(),
  'Measure': MeasureScreen(),
  'Activity': ActivityScreen(),
  'Ring': RingScreen(),
  'Settings': SettingsScreen(),
};

final dataScreens = <String, (Widget, MetricsScenario)>{
  'Today with full data': (const TodayScreen(), fullDataScenario),
  'Today offline': (const TodayScreen(), offlineScenario),
  'Today while the baseline builds': (const TodayScreen(), buildingScenario),
  'Readiness with full data': (const ReadinessScreen(), fullDataScenario),
  'Readiness while the baseline builds': (
    const ReadinessScreen(),
    buildingScenario,
  ),
  'Sleep with full data': (const SleepScreen(), fullDataScenario),
  'Sleep with a split night': (const SleepScreen(), splitNightScenario),
  'Heart with full data': (const HeartScreen(), fullDataScenario),
  'Activity with full data': (const ActivityScreen(), fullDataScenario),
  'Activity while the week fills': (const ActivityScreen(), buildingScenario),
  'Ring with full data': (const RingScreen(), fullDataScenario),
  'Ring offline': (const RingScreen(), offlineScenario),
};

List<Override> Function() _withRing({
  MetricsScenario? scenario,
  RingSyncState? seed,
  MeasureState? measure,
}) => () {
  final data = scenario ?? fullDataScenario;
  return metricsOverrides(
    data,
    ring: ringOverrides(
      paired: data.pairedRing,
      seed: seed,
      measure: measure,
      clock: () => metricsNow,
    ),
  );
};

List<Override> _ringWithLog([MetricsScenario? seen]) => metricsOverrides(
  seen ?? offlineScenario,
  ring: ringOverrides(
    store: FakeSyncStore(
      ring: PairedRing(
        deviceId: fakeRingId,
        lastSyncAt: (seen ?? offlineScenario).ring.lastSyncAt,
        measurements: const AutoMeasurements(
          off: {AutoMeasurement.heartRate, AutoMeasurement.spo2},
        ),
      ),
      runs: [
        for (final outcome in SyncRunOutcome.values)
          SyncRun(
            at: metricsNow.subtract(Duration(days: outcome.index)),
            outcome: outcome,
            kinds: RecordKind.values.toSet(),
            recordCount: 12840,
          ),
      ],
    ),
    clock: () => metricsNow,
  ),
);

const _syncing = RingSyncState(
  progress: SyncProgress(SyncStep.pulling, kind: RecordKind.heartRate),
);

const _aborted = RingSyncState(
  lastError: SyncAborted(SyncStep.connecting, 'GATT_ERROR 133'),
);

final _reading = LiveReading(
  kind: LiveKind.spo2,
  value: 97,
  at: DateTime.utc(2026, 11, 10, 9),
);

final stateScreens = <String, (Widget, List<Override> Function())>{
  'Ring with a sync log and measurements off': (
    const RingScreen(),
    _ringWithLog,
  ),
  'Ring while syncing': (const RingScreen(), _withRing(seed: _syncing)),
  'Ring after a failed sync': (const RingScreen(), _withRing(seed: _aborted)),
  'Ring offline after a partial sync': (
    const RingScreen(),
    _withRing(
      scenario: offlineScenario,
      seed: RingSyncState(
        lastError: CapabilitiesFailed(const [RingCapability.hrv]),
      ),
    ),
  ),
  'Today while syncing': (const TodayScreen(), _withRing(seed: _syncing)),
  'Today after a failed sync': (const TodayScreen(), _withRing(seed: _aborted)),
  'Activity after a failed sync': (
    const ActivityScreen(),
    _withRing(seed: _aborted),
  ),
  'Measure while reading': (
    const MeasureScreen(),
    _withRing(
      measure: const MeasureState(
        phase: MeasurePhase.reading,
        elapsed: Duration(seconds: 12),
        latest: 72,
      ),
    ),
  ),
  'Measure with a result': (
    const MeasureScreen(),
    _withRing(
      measure: MeasureState(
        kind: LiveKind.spo2,
        phase: MeasurePhase.done,
        elapsed: defaultMeasureWindow,
        result: MeasureResult(reading: _reading, saved: false),
      ),
    ),
  ),
  'Measure after a failure': (
    const MeasureScreen(),
    _withRing(
      measure: const MeasureState(
        phase: MeasurePhase.failed,
        failure: MeasureFailure.noReading,
      ),
    ),
  ),
  'Measure without a ring': (
    const MeasureScreen(),
    _withRing(
      scenario: noDataScenario,
      measure: const MeasureState(
        phase: MeasurePhase.failed,
        failure: MeasureFailure.noRing,
      ),
    ),
  ),
};

const _farRing = DiscoveredDevice(
  id: 'AA:BB:CC:00:00:11',
  name: 'COLMI R10_LONG_NAME_7F3A',
  rssi: -88,
);

const List<DiscoveredDevice> _rings = [bondedRing, colmiRing, _farRing];

List<Override> Function() _onboarding({
  PairState? pair,
  Map<AppPermission, PermissionStatus>? permissions,
  RingSyncState? held,
  RingStatus? ring,
  bool paired = false,
}) =>
    () => [
      ...bleOverrides(),
      ...ringOverrides(
        paired: paired ? const PairedRing(deviceId: fakeRingId) : null,
        written: const {RecordKind.heartRate: 1284, RecordKind.sleep: 7},
      ),
      ...onboardingOverrides(
        permissions: FakeAppPermissions(statuses: permissions),
        pairSeed: pair,
      ),
      if (held != null)
        ringSyncProvider.overrideWith(() => HeldRingSyncController(held)),
      if (ring != null)
        ringStatusReaderProvider.overrideWithValue(FakeRingStatusReader(ring)),
    ];

final onboardingScreens = <String, (Widget, List<Override> Function())>{
  'Welcome': (const WelcomeScreen(), _onboarding()),
  'Permissions before asking': (const PermissionsScreen(), _onboarding()),
  'Permissions with one allowed and one blocked': (
    const PermissionsScreen(),
    _onboarding(
      permissions: {
        AppPermission.bluetooth: PermissionStatus.granted,
        AppPermission.notifications: PermissionStatus.permanentlyDenied,
      },
    ),
  ),
  'Profile': (const ProfileScreen(), _onboarding()),
  'Health permission': (const HealthPermissionScreen(), _onboarding()),
  'Health permission connected': (
    const HealthPermissionScreen(initialPhase: HealthConnectPhase.connected),
    _onboarding(),
  ),
  'Health permission declined': (
    const HealthPermissionScreen(initialPhase: HealthConnectPhase.declined),
    _onboarding(),
  ),
  'Pair before searching': (
    const PairScreen(flow: PairFlow.onboarding),
    _onboarding(),
  ),
  'Pair while scanning with rings': (
    const PairScreen(flow: PairFlow.onboarding),
    _onboarding(
      pair: const PairState(
        phase: PairPhase.scanning,
        devices: _rings,
        scanActive: true,
      ),
    ),
  ),
  'Pair after a failed connection': (
    const PairScreen(),
    _onboarding(
      pair: const PairState(
        phase: PairPhase.scanning,
        devices: _rings,
        target: _farRing,
        connectFailed: true,
      ),
    ),
  ),
  'Pair while connecting': (
    const PairScreen(),
    _onboarding(
      pair: const PairState(
        phase: PairPhase.connecting,
        devices: _rings,
        target: colmiRing,
      ),
    ),
  ),
  'Pair with a paired ring': (
    const PairScreen(flow: PairFlow.onboarding),
    _onboarding(
      pair: const PairState(
        phase: PairPhase.paired,
        devices: _rings,
        target: colmiRing,
      ),
    ),
  ),
  for (final failure in PairFailure.values)
    'Pair error ${failure.name}': (
      PairErrorScreen(failure: failure),
      _onboarding(),
    ),
  'First sync while running': (
    const FirstSyncScreen(),
    _onboarding(
      held: const RingSyncState(
        progress: SyncProgress(SyncStep.pulling, kind: RecordKind.stress),
      ),
    ),
  ),
  'First sync with the ring pill': (
    const FirstSyncScreen(),
    _onboarding(
      held: const RingSyncState(
        progress: SyncProgress(SyncStep.pulling, kind: RecordKind.stress),
        batteryPercent: 100,
      ),
      ring: const RingStatus(paired: true, name: 'COLMI R10_LONG_NAME_7F3A'),
    ),
  ),
  'First sync done': (const FirstSyncScreen(), _onboarding(paired: true)),
  'First sync failed': (const FirstSyncScreen(), _onboarding()),
};

Future<void> pumpCase(
  WidgetTester tester,
  Widget widget,
  LayoutCase c, {
  List<Override>? overrides,
}) => pumpScaled(
  tester,
  widget,
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  overrides: overrides,
);

Future<void> visitEveryTab(WidgetTester tester) async {
  for (final tab in AppTab.values) {
    await tester.tap(find.byKey(AppNavigationBar.destinationKey(tab)));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(RingScreen.settingsKey));
  await tester.pumpAndSettle();
}

double navBarHeight(WidgetTester tester) =>
    tester.getSize(find.byType(AppNavigationBar)).height;

void main() {
  for (final MapEntry(key: name, value: screen) in screens.entries) {
    group('$name screen', () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpCase(tester, screenHost(screen), c);

          expect(find.byWidget(screen), findsOneWidget);
          expect(
            Theme.of(tester.element(find.byWidget(screen))).brightness,
            c.brightness,
          );
        });
      }
    });
  }

  for (final MapEntry(key: name, value: (screen, scenario))
      in dataScreens.entries) {
    group(name, () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpCase(
            tester,
            screenHost(screen),
            c,
            overrides: metricsOverrides(scenario),
          );

          expect(find.byWidget(screen), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        });
      }
    });
  }

  for (final MapEntry(key: name, value: (screen, overrides))
      in stateScreens.entries) {
    group(name, () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpCase(tester, screenHost(screen), c, overrides: overrides());

          expect(find.byWidget(screen), findsOneWidget);
        });
      }
    });
  }

  for (final MapEntry(key: name, value: (screen, overrides))
      in onboardingScreens.entries) {
    group(name, () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpCase(tester, screenHost(screen), c, overrides: overrides());

          expect(find.byWidget(screen), findsOneWidget);
        });
      }
    });
  }

  group('Pair error with the model note open', () {
    const screen = PairErrorScreen(failure: PairFailure.notFound);
    for (final c in layoutMatrix()) {
      testWidgets('lays out without overflow at $c', (tester) async {
        await pumpCase(
          tester,
          screenHost(screen),
          c,
          overrides: _onboarding()(),
        );

        await expectNoLayoutOverflow(() async {
          await tester.scrollUntilVisible(
            find.byKey(PairErrorKeys.modelToggle),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(PairErrorKeys.modelToggle));
          await tester.pumpAndSettle();
        });
        expect(find.byType(ExpansionTile), findsOneWidget);
      });
    }
  });

  for (final MapEntry(key: name, value: (action, scenario)) in {
    'Ring unpair dialog': (RingKeys.unpair, offlineScenario),
    'Ring after finding': (RingKeys.find, fullDataScenario),
  }.entries) {
    group(name, () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpCase(
            tester,
            screenHost(const RingScreen()),
            c,
            overrides: _ringWithLog(scenario),
          );

          await expectNoLayoutOverflow(() async {
            await tester.scrollUntilVisible(
              find.byKey(action),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(action));
            await tester.pumpAndSettle();
          });
          final shown = action == RingKeys.unpair
              ? RingKeys.unpairConfirm
              : RingKeys.findStatus;
          expect(find.byKey(shown), findsOneWidget);
        });
      }
    });
  }

  group('Heart metric tabs with full data', () {
    for (final c in layoutMatrix()) {
      testWidgets('every tab lays out without overflow at $c', (tester) async {
        await pumpCase(
          tester,
          screenHost(const HeartScreen()),
          c,
          overrides: metricsOverrides(fullDataScenario),
        );

        await expectNoLayoutOverflow(() async {
          for (final metric in HeartMetric.values) {
            await tester.tap(find.byKey(HeartScreen.metricKey(metric)));
            await tester.pumpAndSettle();
          }
        });
        expect(find.byKey(HeartScreen.insightKey), findsOneWidget);
      });
    }
  });

  group('Sleep score sheet with full data', () {
    for (final c in layoutMatrix()) {
      testWidgets('lays out without overflow at $c', (tester) async {
        await pumpCase(
          tester,
          screenHost(const SleepScreen()),
          c,
          overrides: metricsOverrides(fullDataScenario),
        );

        await expectNoLayoutOverflow(() async {
          await tester.ensureVisible(find.byKey(SleepScreen.scoreKey));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(SleepScreen.scoreKey));
          await tester.pumpAndSettle();
        });
        expect(find.byType(BottomSheet), findsOneWidget);
      });
    }
  });

  group('shell', () {
    for (final c in layoutMatrix()) {
      testWidgets('every tab lays out without overflow at $c', (tester) async {
        await pumpCase(tester, const OpenRingApp(), c);

        await expectNoLayoutOverflow(() => visitEveryTab(tester));
        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('keeps every label visible at $c', (tester) async {
        await pumpCase(tester, const OpenRingApp(), c);

        final bar = tester.getRect(find.byType(AppNavigationBar));
        for (final tab in AppTab.values) {
          final label = find.descendant(
            of: find.byKey(AppNavigationBar.destinationKey(tab)),
            matching: find.byType(Text),
          );
          expect(label, findsOneWidget);
          final rect = tester.getRect(label);
          expect(rect.height, greaterThan(0));
          expect(bar.contains(rect.topLeft), isTrue, reason: tab.name);
          expect(rect.bottom, lessThanOrEqualTo(bar.bottom));
        }
      });
    }

    testWidgets('the bar grows with the text scale instead of clipping', (
      tester,
    ) async {
      const base = LayoutCase(
        scale: 1,
        brightness: Brightness.dark,
        locale: Locale('de'),
      );
      await pumpCase(tester, const OpenRingApp(), base);
      final regular = navBarHeight(tester);

      const large = LayoutCase(
        scale: 2,
        brightness: Brightness.dark,
        locale: Locale('de'),
      );
      await pumpCase(tester, const OpenRingApp(), large);

      expect(navBarHeight(tester), greaterThan(regular));
    });
  });
}
