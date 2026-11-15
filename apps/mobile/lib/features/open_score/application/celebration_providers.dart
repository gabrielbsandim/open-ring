import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/level_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/domain/celebration_store.dart';

final celebrationStoreProvider = Provider<CelebrationStore>(
  (ref) => InMemoryCelebrationStore(),
);

final celebrationClosedProvider =
    AsyncNotifierProvider<CelebrationClosedController, LocalDate?>(
      CelebrationClosedController.new,
    );

class CelebrationClosedController extends AsyncNotifier<LocalDate?> {
  @override
  Future<LocalDate?> build() async =>
      LocalDate.tryParse(await ref.watch(celebrationStoreProvider).read());

  Future<void> close(LocalDate day) async {
    state = AsyncData(day);
    await ref.read(celebrationStoreProvider).write(day.iso);
  }
}

typedef TodayCelebration = ({LocalDate today, LevelCelebration earned});

/// What yesterday earned, or null when there is nothing to show: nothing
/// earned, no Level yet, or the card already closed today.
final levelCelebrationProvider = FutureProvider<TodayCelebration?>((ref) async {
  final (history, track, tags, goal, closed) = await (
    ref.watch(dayScoreHistoryProvider.future),
    ref.watch(levelTrackProvider.future),
    ref.watch(dayTagsProvider.future),
    ref.watch(weekGoalProvider.future),
    ref.watch(celebrationClosedProvider.future),
  ).wait;
  if (track.level == null || closed == history.today) return null;
  final earned = levelCelebration(
    track,
    today: history.today,
    goal: goal,
    tagged: tags.keys.toSet(),
  );
  return earned.isEmpty ? null : (today: history.today, earned: earned);
});
