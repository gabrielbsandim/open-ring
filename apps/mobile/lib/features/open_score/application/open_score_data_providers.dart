import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/open_score/application/celebration_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';

/// How many day tags are stored, for the Open Score module screen.
final openScoreTagCountProvider = FutureProvider<int>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(dayTagStoreProvider).count();
});

/// Clears the day tags, the weekly goal and the closed celebration date.
/// False when a store failed; what is on screen is refreshed either way.
Future<bool> clearOpenScoreData(WidgetRef ref) async {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final tags = ref.read(dayTagStoreProvider);
  final goal = ref.read(weekGoalStoreProvider);
  final celebration = ref.read(celebrationStoreProvider);
  try {
    await tags.clear();
    await goal.clear();
    await celebration.clear();
    return true;
  } on Object {
    return false;
  } finally {
    container
      ..invalidate(weekGoalProvider)
      ..invalidate(celebrationClosedProvider)
      ..read(dataRevisionProvider.notifier).bump();
  }
}
