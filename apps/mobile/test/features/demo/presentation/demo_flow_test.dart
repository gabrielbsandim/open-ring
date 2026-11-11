import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/demo/presentation/demo_banner.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_cards.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/demo_fakes.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

final class DemoApp {
  new({bool demo = false})
    : store = InMemoryDemoModeStore(enabled: demo),
      onboarding = InMemoryOnboardingStore(completed: demo);

  final InMemoryDemoModeStore store;
  final InMemoryOnboardingStore onboarding;
  final data = RecordingDemoDataStore();
  final scheduler = FakeSyncScheduler();

  Future<void> pump(WidgetTester tester) => pumpOnboardingApp(
    tester,
    store: onboarding,
    overrides: [
      ...bleOverrides(),
      ...ringOverrides(scheduler: scheduler),
      ...onboardingOverrides(),
      ...demoOverrides(store: store, data: data),
      ringStatusReaderProvider.overrideWithValue(
        FakeRingStatusReader(
          RingStatus(
            paired: true,
            name: 'R09 Demo',
            model: 'R09',
            lastSyncAt: DateTime.now(),
            batteryPercent: 76,
          ),
        ),
      ),
    ],
  );
}

Future<void> openTab(WidgetTester tester, AppTab tab) async {
  await tester.tap(find.byKey(AppNavigationBar.destinationKey(tab)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('exploring without a ring opens Today in the demo', (
    tester,
  ) async {
    final app = DemoApp();
    await app.pump(tester);

    expect(find.text('Explore without a ring'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(WelcomeScreen.demoKey));

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byKey(DemoKeys.banner), findsOneWidget);
    expect(find.text('Leave demo'), findsOneWidget);
    expect(app.store.enabled, isTrue);
    expect(app.onboarding.completed, isTrue);
    expect(app.data.replaced, hasLength(1));
    expect(app.scheduler.cancels, 1);
  });

  testWidgets('every tab is reachable and keeps the demo banner', (
    tester,
  ) async {
    final app = DemoApp(demo: true);
    await app.pump(tester);

    final screens = <AppTab, Type>{
      AppTab.sleep: SleepScreen,
      AppTab.heart: HeartScreen,
      AppTab.activity: ActivityScreen,
      AppTab.ring: RingScreen,
      AppTab.today: TodayScreen,
    };
    for (final MapEntry(key: tab, value: screen) in screens.entries) {
      await openTab(tester, tab);
      expect(find.byType(screen), findsOneWidget, reason: tab.name);
      expect(find.byKey(DemoKeys.banner), findsOneWidget, reason: tab.name);
    }
  });

  testWidgets('the Ring tab offers to leave the demo instead of unpairing', (
    tester,
  ) async {
    final app = DemoApp(demo: true);
    await app.pump(tester);
    await openTab(tester, AppTab.ring);

    await tester.scrollUntilVisible(find.byKey(DemoKeys.ringLeave), 120);

    expect(find.byKey(DemoKeys.ringLeave), findsOneWidget);
    expect(find.byKey(RingKeys.unpair), findsNothing);
  });

  testWidgets('leaving the demo deletes its data and returns to Welcome', (
    tester,
  ) async {
    final app = DemoApp(demo: true);
    await app.pump(tester);

    await tester.tap(find.byKey(DemoKeys.leave));
    await tester.pumpAndSettle();
    expect(find.text('Leave demo mode?'), findsOneWidget);
    await tester.tap(find.byKey(DemoKeys.leaveConfirm));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byKey(DemoKeys.banner), findsNothing);
    expect(app.data.wipes, 1);
    expect(app.store.enabled, isFalse);
    expect(app.onboarding.completed, isFalse);
  });

  testWidgets('cancelling keeps the demo and its data', (tester) async {
    final app = DemoApp(demo: true);
    await app.pump(tester);

    await tester.tap(find.byKey(DemoKeys.leave));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DemoKeys.leaveCancel));
    await tester.pumpAndSettle();

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byKey(DemoKeys.banner), findsOneWidget);
    expect(app.data.wipes, 0);
    expect(app.store.enabled, isTrue);
  });

  testWidgets('a failed seed stays on Welcome and says so', (tester) async {
    final app = DemoApp();
    app.data.replaceError = StateError('disk full');
    await app.pump(tester);

    await tapAndSettle(tester, find.byKey(WelcomeScreen.demoKey));

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(
      find.text('Could not load the sample data. Try again.'),
      findsOneWidget,
    );
    expect(app.store.enabled, isFalse);
  });
}
