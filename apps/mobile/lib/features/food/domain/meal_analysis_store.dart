import 'package:open_ring/features/food/domain/meal_analysis.dart';

/// Analyses live and die with their meal and never touch a meal tag.
abstract interface class MealAnalysisStore {
  /// One row per (meal, host, model, prompt version). A stored answer comes
  /// back as is unless the output schema or photo differs or [again] is set,
  /// which resets the row to queued and keeps user items and hidden chips.
  Future<MealAnalysis> enqueue(
    int mealId,
    String photoName,
    MealAnalysisTarget target, {
    required DateTime now,
    bool again = false,
  });

  Future<List<MealAnalysis>> byMeal(int mealId);

  /// The oldest queued row.
  Future<MealAnalysis?> next();

  /// Queued to sending, counting the attempt.
  Future<bool> markSending(int id, {required DateTime now});

  /// Writes a sending row's answer and replaces its model items.
  Future<bool> complete(
    int id,
    MealAnalysisAnswer answer, {
    required DateTime now,
  });

  /// Queued or sending to failed.
  Future<bool> fail(int id, String errorKind, {required DateTime now});

  /// Queued to skipped.
  Future<bool> skip(int id, String reason, {required DateTime now});

  /// Skipped rows excluded.
  Future<int> countQueuedSince(DateTime since);

  Future<int> expireBefore(DateTime cutoff, {required DateTime now});

  Future<int> skipOffTarget(
    String providerHost,
    String model, {
    required DateTime now,
  });

  Future<int> recoverInterrupted({required DateTime now});

  /// By the time each row was last written.
  Future<int> purgeRawBefore(DateTime cutoff);

  Future<bool> keepOnPhone(int mealId);

  Future<bool> setKeepOnPhone(int mealId, {required bool keep});

  /// `keep_on_phone` stays with the meal.
  Future<void> deleteAll();
}
