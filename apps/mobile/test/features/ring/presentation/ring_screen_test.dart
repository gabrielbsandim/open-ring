import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_cards.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';

import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

Future<void> _pumpRing(
  WidgetTester tester,
  MetricsScenario scenario, {
  FakeRingDriver? driver,
  RingSyncState? seed,
  Widget app = const RingScreen(),
}) => pumpScaled(
  tester,
  app is RingScreen ? screenHost(app) : app,
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: metricsOverrides(
    scenario,
    ring: ringOverrides(
      paired: scenario.pairedRing,
      driver: driver,
      seed: seed,
      clock: () => metricsNow,
    ),
  ),
);

void main() {
  testWidgets('unpaired points to pairing', (tester) async {
    await _pumpRing(tester, noDataScenario, app: const OpenRingApp());
    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
    await tester.pumpAndSettle();

    expect(find.text('No ring paired'), findsOneWidget);
    expect(find.textContaining('COLMI R09'), findsOneWidget);
    expect(find.byKey(RingKeys.sync), findsNothing);

    await tester.tap(find.byKey(RingScreen.pairKey));
    await tester.pumpAndSettle();

    expect(find.byType(PairScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(PairKeys.search),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(PairKeys.search), findsOneWidget);
  });

  testWidgets('a fresh ring shows device, battery and sync times', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpRing(tester, fullDataScenario);

    expect(find.byKey(RingKeys.device), findsOneWidget);
    expect(find.text('R09_C0FE'), findsOneWidget);
    expect(find.text('Model R09 · Firmware 3.00.03'), findsOneWidget);
    expect(find.bySemanticsLabel('Battery 68%, charging'), findsOneWidget);
    expect(find.text('Connects only while it syncs'), findsOneWidget);
    expect(find.byKey(RingKeys.offline), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(RingKeys.lastSync),
        matching: find.text('08:40'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(RingKeys.nextSync),
        matching: find.text('09:40'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('picking an interval saves it', (tester) async {
    await _pumpRing(tester, fullDataScenario);

    final option = find.byKey(RingKeys.intervalOption(SyncInterval.minutes30));
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RingScreen)),
    );
    expect(container.read(syncIntervalProvider), SyncInterval.minutes30);
    expect(find.text('Automatic every 30 min'), findsOneWidget);
  });

  testWidgets('sync now connects to the ring', (tester) async {
    final driver = FakeRingDriver();
    await _pumpRing(tester, fullDataScenario, driver: driver);

    await tester.tap(find.byKey(RingKeys.syncNow));
    await tester.pumpAndSettle();

    expect(driver.connects, 1);
    expect(driver.disconnects, 1);
  });

  testWidgets('an offline ring says what to try', (tester) async {
    await _pumpRing(tester, offlineScenario);

    expect(find.byKey(RingKeys.offline), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.textContaining('Last seen'), findsOneWidget);
    expect(find.text('What to try'), findsOneWidget);
    expect(find.textContaining('The last reading was 14%'), findsOneWidget);
    expect(find.textContaining('Nothing is lost'), findsOneWidget);
    await reveal(tester, find.byKey(RingKeys.unpair));
    expect(find.text('Unpair ring'), findsOneWidget);
    expect(find.byKey(RingKeys.find), findsNothing);
  });

  testWidgets('a running sync shows its step and disables sync now', (
    tester,
  ) async {
    await _pumpRing(
      tester,
      fullDataScenario,
      seed: const RingSyncState(
        progress: SyncProgress(SyncStep.pulling, kind: RecordKind.heartRate),
      ),
    );

    expect(find.byKey(SyncKeys.progress), findsOneWidget);
    expect(find.text('Fetching heart rate'), findsOneWidget);
    expect(find.text('Connected, syncing'), findsOneWidget);
    expect(find.byKey(RingKeys.offline), findsNothing);
    final button = find.ancestor(
      of: find.text('Syncing…'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(button).enabled, isFalse);
  });

  testWidgets('a failed sync shows the error with a retry', (tester) async {
    final driver = FakeRingDriver();
    await _pumpRing(
      tester,
      fullDataScenario,
      driver: driver,
      seed: const RingSyncState(
        lastError: SyncAborted(SyncStep.connecting, 'GATT_ERROR 133'),
      ),
    );

    expect(find.byKey(SyncKeys.error), findsOneWidget);
    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.textContaining('Could not reach the ring'), findsOneWidget);
    expect(find.textContaining('GATT_ERROR'), findsNothing);

    await tester.ensureVisible(find.byKey(SyncKeys.retry));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SyncKeys.retry));
    await tester.pumpAndSettle();

    expect(driver.connects, 1);
  });
}
