import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/food/domain/meal_analysis_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_analysis_store.dart';

final mealAnalysisStoreProvider = Provider<MealAnalysisStore>(
  (ref) => throw UnimplementedError('Override mealAnalysisStoreProvider.'),
);

final Override driftMealAnalysisStoreOverride = mealAnalysisStoreProvider
    .overrideWith(
      (ref) => DriftMealAnalysisStore(
        ref.watch(appDatabaseProvider),
        onWrite: () => ref.read(mealAnalysisRevisionProvider.notifier).bump(),
      ),
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
