import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';

final mealAnalysisStoreProvider = Provider<MealAnalysisStore>(
  (ref) => throw UnimplementedError('Override mealAnalysisStoreProvider.'),
);

// Separate from dataRevisionProvider: a suggestion changes no metric until
// the person confirms it through MealStore, which bumps that one.
final mealAnalysisRevisionProvider =
    NotifierProvider<MealAnalysisRevision, int>(MealAnalysisRevision.new);

class MealAnalysisRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
