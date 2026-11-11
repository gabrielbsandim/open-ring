import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

final userProfileStoreProvider = Provider<UserProfileStore>(
  (ref) => InMemoryUserProfileStore(),
);

final userProfileProvider =
    AsyncNotifierProvider<UserProfileController, UserProfile?>(
      UserProfileController.new,
    );

class UserProfileController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() => ref.watch(userProfileStoreProvider).read();

  Future<void> save(UserProfile profile) async {
    await ref
        .read(userProfileStoreProvider)
        .save(profile, at: ref.read(clockProvider)());
    if (!ref.mounted) return;
    state = AsyncData(profile);
  }
}
