import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
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

/// Every analysis row of a meal, the latest first.
final FutureProviderFamily<List<MealAnalysis>, int> mealAnalysesProvider =
    FutureProvider.family<List<MealAnalysis>, int>((ref, mealId) async {
      ref.watch(mealAnalysisRevisionProvider);
      final rows = await ref.watch(mealAnalysisStoreProvider).byMeal(mealId);
      return [...rows]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    });

final FutureProviderFamily<bool, int> mealKeepOnPhoneProvider =
    FutureProvider.family<bool, int>((ref, mealId) {
      ref.watch(mealAnalysisRevisionProvider);
      return ref.watch(mealAnalysisStoreProvider).keepOnPhone(mealId);
    });
