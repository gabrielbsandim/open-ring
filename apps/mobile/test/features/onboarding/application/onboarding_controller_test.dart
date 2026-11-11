import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';

import '../../../helpers/onboarding_fakes.dart';

void main() {
  test('completing onboarding saves once', () async {
    final store = InMemoryOnboardingStore();
    final container = ProviderContainer(
      overrides: [onboardingStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(container.read(onboardingProvider), isFalse);
    await container.read(onboardingProvider.notifier).complete();
    await container.read(onboardingProvider.notifier).complete();

    expect(container.read(onboardingProvider), isTrue);
    expect(store.writes, 1);
  });

  test('permissions load, update on request and recheck', () async {
    final permissions = FakeAppPermissions(
      statuses: {AppPermission.notifications: PermissionStatus.granted},
    );
    final container = ProviderContainer(
      overrides: onboardingOverrides(permissions: permissions),
    );
    addTearDown(container.dispose);
    container.listen(permissionsProvider, (_, _) {});

    expect(await container.read(permissionsProvider.future), {
      AppPermission.bluetooth: PermissionStatus.denied,
      AppPermission.notifications: PermissionStatus.granted,
      AppPermission.backgroundExecution: PermissionStatus.denied,
      AppPermission.location: PermissionStatus.denied,
    });

    await container
        .read(permissionsProvider.notifier)
        .request(AppPermission.bluetooth);
    expect(
      container.read(permissionsProvider).value?[AppPermission.bluetooth],
      PermissionStatus.granted,
    );

    permissions.statuses[AppPermission.notifications] =
        PermissionStatus.permanentlyDenied;
    await container.read(permissionsProvider.notifier).recheck();
    expect(
      container.read(permissionsProvider).value?[AppPermission.notifications],
      PermissionStatus.permanentlyDenied,
    );
  });

  group('onboarding redirect', () {
    test('before onboarding every app location leads to onboarding', () {
      for (final location in [AppTab.today.path, AppPaths.settings, '/']) {
        expect(
          onboardingRedirect(completed: false, location: location),
          AppPaths.onboarding,
        );
      }
    });

    test('before onboarding its own steps stay reachable', () {
      for (final location in [
        AppPaths.onboarding,
        AppPaths.onboardingProfile,
        PairFlow.onboarding.syncPath,
      ]) {
        expect(
          onboardingRedirect(completed: false, location: location),
          isNull,
        );
      }
    });

    test('after onboarding nothing is redirected', () {
      expect(
        onboardingRedirect(completed: true, location: AppTab.today.path),
        isNull,
      );
      expect(
        onboardingRedirect(
          completed: true,
          location: PairFlow.onboarding.syncPath,
        ),
        isNull,
      );
    });
  });
}
