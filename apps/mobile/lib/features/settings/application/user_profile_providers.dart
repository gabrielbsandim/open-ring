import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
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

  // The goal history is written first: a failed profile save is fixed by a
  // retry, a missing row would rescore the past without a trace.
  Future<void> save(UserProfile profile) async {
    final previous = (await future)?.dailyStepGoal ?? defaultStepGoal;
    final next = profile.dailyStepGoal ?? defaultStepGoal;
    if (next != previous) {
      await ref
          .read(stepGoalHistoryProvider)
          .record(
            on: ref.read(currentDateProvider),
            steps: next,
            previous: previous,
          );
      ref.read(dataRevisionProvider.notifier).bump();
    }
    await ref
        .read(userProfileStoreProvider)
        .save(profile, at: ref.read(clockProvider)());
    if (!ref.mounted) return;
    state = AsyncData(profile);
  }
}
