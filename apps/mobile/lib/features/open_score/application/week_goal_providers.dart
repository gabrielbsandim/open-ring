import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/level_providers.dart';
import 'package:open_ring/features/open_score/domain/week_goal_store.dart';

final weekGoalStoreProvider = Provider<WeekGoalStore>(
  (ref) => InMemoryWeekGoalStore(),
);

final weekGoalProvider = AsyncNotifierProvider<WeekGoalController, int>(
  WeekGoalController.new,
);

class WeekGoalController extends AsyncNotifier<int> {
  @override
  Future<int> build() async => clampWeekGoal(
    await ref.watch(weekGoalStoreProvider).read() ?? weekGoalDefault,
  );

  Future<void> set(int goal) async {
    final next = clampWeekGoal(goal);
    state = AsyncData(next);
    await ref.read(weekGoalStoreProvider).write(next);
  }
}

final levelWeekProvider = FutureProvider<LevelWeek>((ref) async {
  final (history, track, tags, goal) = await (
    ref.watch(dayScoreHistoryProvider.future),
    ref.watch(levelTrackProvider.future),
    ref.watch(dayTagsProvider.future),
    ref.watch(weekGoalProvider.future),
  ).wait;
  return levelWeek(
    track,
    today: history.today,
    goal: goal,
    tagged: tags.keys.toSet(),
  );
});

final levelBestsProvider = FutureProvider<LevelBests>((ref) async {
  final (history, track) = await (
    ref.watch(dayScoreHistoryProvider.future),
    ref.watch(levelTrackProvider.future),
  ).wait;
  return levelBests(track, today: history.today);
});
