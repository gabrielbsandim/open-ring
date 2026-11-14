import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/presentation/first_sync_screen.dart';
import 'package:open_ring/features/onboarding/presentation/health_permission_screen.dart';
import 'package:open_ring/features/onboarding/presentation/permissions_screen.dart';
import 'package:open_ring/features/onboarding/presentation/profile_screen.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../helpers/ble_fakes.dart';
import '../helpers/fake_health_writer.dart';
import '../helpers/onboarding_app.dart';
import '../helpers/onboarding_fakes.dart';
import '../helpers/ring_fakes.dart';

void main() {
  testWidgets('a first launch opens onboarding', (tester) async {
    await pumpOnboardingApp(tester);

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
  });

  testWidgets('a finished onboarding opens Today', (tester) async {
    await pumpOnboardingApp(
      tester,
      store: InMemoryOnboardingStore(completed: true),
    );

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('an app location leads back to onboarding until it is done', (
    tester,
  ) async {
    final container = await pumpOnboardingApp(tester);

    container.read(appRouterProvider).go(AppPaths.settings);
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('the whole flow pairs a ring, syncs and lands on Today', (
    tester,
  ) async {
    final store = InMemoryOnboardingStore();
    final pairedStore = RecordingPairedRingStore();
    await pumpOnboardingApp(
      tester,
      store: store,
      overrides: [
        ...bleOverrides(scanner: FakeRingScanner(found: const [colmiRing])),
        ...ringOverrides(paired: PairedRing(deviceId: colmiRing.id)),
        ...onboardingOverrides(
          pairedStore: pairedStore,
          healthWriter: FakeHealthWriter()..denied.addAll(writableHealthKinds),
        ),
      ],
    );

    await tapAndSettle(tester, find.byKey(WelcomeScreen.startKey));
    expect(find.byType(PermissionsScreen), findsOneWidget);
    await tapAndSettle(
      tester,
      find.byKey(PermissionsKeys.allow(AppPermission.bluetooth)),
    );
    await tapAndSettle(tester, find.byKey(PermissionsKeys.continueAction));
    expect(find.byType(ProfileScreen), findsOneWidget);
    await tapAndSettle(tester, find.byKey(ProfileKeys.skip));
    expect(find.byType(HealthPermissionScreen), findsOneWidget);
    await tapAndSettle(tester, find.byKey(HealthPermissionKeys.notNow));
    expect(find.byType(PairScreen), findsOneWidget);
    expect(store.completed, isFalse);

    await tapAndSettle(tester, find.byKey(PairKeys.search));
    await tapAndSettle(tester, find.byKey(PairKeys.device(colmiRing.id)));
    expect(find.byKey(PairKeys.paired), findsOneWidget);
    expect(store.completed, isTrue);
    expect(pairedStore.saved.single.deviceId, colmiRing.id);

    await tapAndSettle(tester, find.byKey(PairKeys.continueAction));
    expect(find.byType(FirstSyncScreen), findsOneWidget);
    expect(find.byKey(FirstSyncKeys.done), findsOneWidget);

    await tapAndSettle(tester, find.byKey(FirstSyncKeys.viewDay));
    expect(find.byType(TodayScreen), findsOneWidget);
  });
}
