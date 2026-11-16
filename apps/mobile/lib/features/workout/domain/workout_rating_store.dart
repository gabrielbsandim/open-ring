import 'package:metrics/metrics.dart';

/// The effort a person gave one workout, from [effortMinRating] to
/// [effortMaxRating]; null is a workout nobody rated.
abstract interface class WorkoutRatingStore {
  /// False when no recorded workout has [id]. Null clears the rating.
  Future<bool> rateRecorded(int id, int? rating);

  /// False when no imported workout has [recordId]. Null clears the rating.
  Future<bool> rateImported(String recordId, int? rating);
}

bool isEffortRating(int rating) =>
    rating >= effortMinRating && rating <= effortMaxRating;

/// A stored value outside the scale reads as no rating.
int? storedRatingOf(int? stored) {
  if (stored == null || !isEffortRating(stored)) return null;
  return stored;
}
