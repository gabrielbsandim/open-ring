import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/ring_fakes.dart';

const _refreshable = <String, Widget>{
  'Today': TodayScreen(),
  'Sleep': SleepScreen(),
  'Heart': HeartScreen(),
  'Activity': ActivityScreen(),
  'Ring': RingScreen(),
};

Future<void> _pump(
  WidgetTester tester,
  Widget widget, {
  FakeRingDriver? driver,
  RingSyncState? seed,
  MetricsScenario? scenario,
}) {
  final data = scenario ?? fullDataScenario;
  return pumpScaled(
    tester,
    widget is OpenRingApp ? widget : screenHost(widget),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    overrides: metricsOverrides(
      data,
      ring: ringOverrides(
        paired: data.pairedRing,
        driver: driver,
        seed: seed,
        clock: () => metricsNow,
      ),
    ),
  );
}

void main() {
  for (final MapEntry(key: name, value: screen) in _refreshable.entries) {
    testWidgets('pulling $name down syncs the ring', (tester) async {
      final driver = FakeRingDriver();
      await _pump(tester, screen, driver: driver);

      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(driver.connects, 1);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
    });
  }

  testWidgets('the banner stays hidden while idle', (tester) async {
    await _pump(tester, const TodayScreen());

    expect(find.byKey(SyncKeys.progress), findsNothing);
    expect(find.byKey(SyncKeys.error), findsNothing);
  });

  testWidgets('the banner shows the running step', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const SleepScreen(),
      seed: const RingSyncState(
        progress: SyncProgress(SyncStep.pulling, kind: RecordKind.sleep),
      ),
    );

    expect(find.byKey(SyncKeys.progress), findsOneWidget);
    expect(find.bySemanticsLabel('Syncing: Fetching sleep'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a partial sync names what is missing and retries', (
    tester,
  ) async {
    final driver = FakeRingDriver();
    await _pump(
      tester,
      const HeartScreen(),
      driver: driver,
      seed: RingSyncState(
        lastSuccessAt: metricsNow,
        lastError: CapabilitiesFailed(const [RingCapability.hrv]),
      ),
    );

    expect(find.text('Sync incomplete'), findsOneWidget);
    expect(find.textContaining('HRV'), findsWidgets);

    await tester.tap(find.byKey(SyncKeys.retry));
    await tester.pumpAndSettle();

    expect(driver.connects, 1);
  });

  testWidgets('without a ring the banner opens the Ring tab', (tester) async {
    await _pump(
      tester,
      const OpenRingApp(),
      scenario: noDataScenario,
      seed: const RingSyncState(lastError: NoPairedRing()),
    );

    expect(find.byKey(SyncKeys.retry), findsNothing);
    await tester.tap(find.byKey(SyncKeys.pair));
    await tester.pumpAndSettle();

    expect(find.byType(RingScreen), findsOneWidget);
  });
}
