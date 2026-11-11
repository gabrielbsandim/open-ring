import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/domain/onboarding_store.dart';

final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => throw UnimplementedError('Override onboardingStoreProvider.'),
);

final appPermissionsProvider = Provider<AppPermissions>(
  (ref) => throw UnimplementedError('Override appPermissionsProvider.'),
);

final onboardingProvider = NotifierProvider<OnboardingController, bool>(
  OnboardingController.new,
);

class OnboardingController extends Notifier<bool> {
  @override
  bool build() => ref.watch(onboardingStoreProvider).completed;

  Future<void> complete() async {
    if (state) return;
    state = true;
    await ref.read(onboardingStoreProvider).complete();
  }

  Future<void> reset() async {
    state = false;
    await ref.read(onboardingStoreProvider).reset();
  }
}

typedef PermissionStatuses = Map<AppPermission, PermissionStatus>;

final AsyncNotifierProvider<PermissionsController, PermissionStatuses>
permissionsProvider = AsyncNotifierProvider.autoDispose(
  PermissionsController.new,
);

class PermissionsController extends AsyncNotifier<PermissionStatuses> {
  AppPermissions get _permissions => ref.read(appPermissionsProvider);

  @override
  Future<PermissionStatuses> build() =>
      _statuses(ref.watch(appPermissionsProvider));

  Future<void> request(AppPermission permission) async {
    final status = await _permissions.request(permission);
    if (!ref.mounted) return;
    state = AsyncData({...?state.value, permission: status});
  }

  Future<void> openSettings() => _permissions.openSettings();

  Future<void> recheck() async {
    final fresh = await _statuses(_permissions);
    if (!ref.mounted) return;
    state = AsyncData(fresh);
  }

  static Future<PermissionStatuses> _statuses(
    AppPermissions permissions,
  ) async => {
    for (final permission in AppPermission.values)
      permission: await permissions.status(permission),
  };
}
