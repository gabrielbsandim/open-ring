import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

/// What the Goals tables hold on this phone, for the module screen.
@immutable
final class GoalsDataCount {
  const new({
    required this.goals,
    required this.reviews,
    required this.screenings,
  });

  final int goals;

  /// Reviewed weeks across every goal, ended ones included.
  final int reviews;
  final int screenings;

  int get total => goals + reviews + screenings;

  @override
  bool operator ==(Object other) =>
      other is GoalsDataCount &&
      other.goals == goals &&
      other.reviews == reviews &&
      other.screenings == screenings;

  @override
  int get hashCode => Object.hash(goals, reviews, screenings);
}

// Not gated on the module: data kept while Goals is off can still be deleted.
final goalsDataCountProvider = FutureProvider<GoalsDataCount>((ref) async {
  ref.watch(dataRevisionProvider);
  final store = ref.watch(goalStoreProvider);
  final goals = await store.goals();
  var reviews = 0;
  for (final goal in goals) {
    reviews += (await store.weeks(goal.id)).length;
  }
  return GoalsDataCount(
    goals: goals.length,
    reviews: reviews,
    screenings: (await store.screenings()).length,
  );
});

final goalsDataEraserProvider = Provider<GoalsDataEraser>(GoalsDataEraser.new);

class GoalsDataEraser {
  const new(this._ref);

  final Ref _ref;

  /// Empties the goals, their weeks and the screenings. Weigh-ins and the
  /// profile step goal belong to other features and stay. False, with the
  /// error logged and nothing bumped, when the store throws.
  Future<bool> clear() async {
    try {
      await _ref.read(goalStoreProvider).clear();
    } on Object catch (error) {
      debugPrint('Goals data was not deleted: $error');
      return false;
    }
    _ref.read(dataRevisionProvider.notifier).bump();
    return true;
  }
}

/// The stored line of the module screen: the counts, then the screening
/// sentence when one is kept, or the empty line.
String goalsDataLine(AppLocalizations l10n, GoalsDataCount count) {
  if (count.total == 0) return l10n.moduleGoalsDataEmpty;
  final screening = count.screenings > 0 ? l10n.moduleGoalsDataScreening : '';
  if (count.goals == 0) return screening;
  final counts = l10n.moduleGoalsDataCount(count.goals, count.reviews);
  return [counts, screening].where((part) => part.isNotEmpty).join(' ');
}
