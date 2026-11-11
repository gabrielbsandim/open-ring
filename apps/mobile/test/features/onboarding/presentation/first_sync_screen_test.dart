import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/onboarding/presentation/first_sync_screen.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

Future<void> _pump(WidgetTester tester, {FakeRingDriver? driver}) =>
    pumpOnboardingApp(
      tester,
      at: PairFlow.onboarding.syncPath,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(
          paired: const PairedRing(deviceId: fakeRingId),
          driver: driver,
          written: const {RecordKind.heartRate: 42, RecordKind.sleep: 1},
        ),
        ...onboardingOverrides(),
      ],
    );

Future<void> _pumpRunning(
  WidgetTester tester,
  RingStatus ring, {
  int? batteryPercent,
}) => pumpOnboardingApp(
  tester,
  at: PairFlow.onboarding.syncPath,
  store: InMemoryOnboardingStore(completed: true),
  overrides: <Override>[
    ...bleOverrides(),
    ...ringOverrides(),
    ...onboardingOverrides(),
    ringStatusReaderProvider.overrideWithValue(FakeRingStatusReader(ring)),
    ringSyncProvider.overrideWith(
      () => HeldRingSyncController(
        RingSyncState(
          progress: const SyncProgress(SyncStep.pulling, kind: RecordKind.hrv),
          batteryPercent: batteryPercent,
        ),
      ),
    ),
  ],
);

Finder _pillText(String text) => find.descendant(
  of: find.byKey(FirstSyncKeys.ring),
  matching: find.text(text),
);

Finder _kindText(RecordKind kind, String text) => find.descendant(
  of: find.byKey(FirstSyncKeys.kind(kind)),
  matching: find.text(text),
);

void main() {
  testWidgets('shows the progress of each kind while the sync runs', (
    tester,
  ) async {
    await pumpOnboardingApp(
      tester,
      at: PairFlow.onboarding.syncPath,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        ringSyncProvider.overrideWith(
          () => HeldRingSyncController(
            const RingSyncState(
              progress: SyncProgress(SyncStep.pulling, kind: RecordKind.spo2),
            ),
          ),
        ),
      ],
    );

    expect(find.text('Syncing'), findsOneWidget);
    expect(find.byKey(FirstSyncKeys.progress), findsOneWidget);
    expect(_kindText(RecordKind.heartRate, 'Read'), findsOneWidget);
    expect(_kindText(RecordKind.spo2, 'Reading…'), findsOneWidget);
    expect(_kindText(RecordKind.sleep, 'Queued'), findsOneWidget);
    expect(find.byKey(FirstSyncKeys.viewDay), findsNothing);
  });

  testWidgets('the overall bar uses the primary text color', (tester) async {
    await _pumpRunning(tester, const RingStatus(paired: true, model: 'R09'));

    final bar = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(FirstSyncKeys.progress),
        matching: find.byType(LinearProgressIndicator),
      ),
    );

    final colors = AppColors.of(tester.element(find.byType(FirstSyncScreen)));
    expect(bar.color, colors.textPrimary);
    expect(bar.value, closeTo(8 / 11, 0.001));
  });

  testWidgets('the pill shows the battery the running sync just read', (
    tester,
  ) async {
    await _pumpRunning(
      tester,
      const RingStatus(paired: true, model: 'R09', batteryPercent: 40),
      batteryPercent: 68,
    );

    expect(_pillText('R09 · 68%'), findsOneWidget);
  });

  testWidgets('the pill falls back to the stored battery reading', (
    tester,
  ) async {
    await _pumpRunning(
      tester,
      const RingStatus(paired: true, model: 'R09', batteryPercent: 40),
    );

    expect(_pillText('R09 · 40%'), findsOneWidget);
  });

  testWidgets('the pill shows no number when no battery was read', (
    tester,
  ) async {
    await _pumpRunning(tester, const RingStatus(paired: true, model: 'R09'));

    expect(_pillText('R09'), findsOneWidget);
  });

  testWidgets('no pill without a paired ring', (tester) async {
    await _pumpRunning(tester, RingStatus.unpaired, batteryPercent: 68);

    expect(find.byKey(FirstSyncKeys.ring), findsNothing);
  });

  testWidgets('a real sync feeds the pill from the driver', (tester) async {
    final driver = FakeRingDriver()
      ..battery = const BatteryStatus(percent: 68, charging: false);
    await pumpOnboardingApp(
      tester,
      at: PairFlow.onboarding.syncPath,
      store: InMemoryOnboardingStore(completed: true),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(
          paired: const PairedRing(deviceId: fakeRingId),
          driver: driver,
        ),
        ...onboardingOverrides(),
        ringStatusReaderProvider.overrideWithValue(
          FakeRingStatusReader(const RingStatus(paired: true, model: 'R09')),
        ),
      ],
    );

    expect(find.byKey(FirstSyncKeys.done), findsOneWidget);
    expect(_pillText('R09 · 68%'), findsOneWidget);
  });

  testWidgets('a finished sync counts what was saved and opens Today', (
    tester,
  ) async {
    final driver = FakeRingDriver();
    await _pump(tester, driver: driver);

    expect(driver.connects, 1);
    expect(find.byKey(FirstSyncKeys.done), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(_kindText(RecordKind.heartRate, '42 records'), findsOneWidget);
    expect(_kindText(RecordKind.sleep, '1 record'), findsOneWidget);
    expect(_kindText(RecordKind.spo2, 'Nothing new'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(FirstSyncKeys.viewDay));

    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('a failed sync can be retried or skipped', (tester) async {
    final driver = FakeRingDriver()
      ..connectError = const BleTransportException('GATT_ERROR 133');
    await _pump(tester, driver: driver);

    expect(find.byKey(FirstSyncKeys.failure), findsOneWidget);
    expect(_kindText(RecordKind.heartRate, 'Not read'), findsOneWidget);
    expect(find.byKey(FirstSyncKeys.skip), findsOneWidget);

    driver.connectError = null;
    await tapAndSettle(tester, find.byKey(FirstSyncKeys.retry));

    expect(driver.connects, 2);
    expect(find.byKey(FirstSyncKeys.done), findsOneWidget);
  });

  testWidgets('skipping a failed sync still opens Today', (tester) async {
    final driver = FakeRingDriver()
      ..connectError = const BleTransportException('GATT_ERROR 133');
    await _pump(tester, driver: driver);

    await tapAndSettle(tester, find.byKey(FirstSyncKeys.skip));

    expect(find.byType(TodayScreen), findsOneWidget);
  });
}
