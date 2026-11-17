import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/domain/meal.dart';

/// Never touches photo files: callers delete the rows first and then the
/// files it names, so no row ever points at a missing photo.
abstract interface class MealStore {
  Future<Meal> add(MealDraft draft, {required DateTime now, String? photo});

  /// Writes the time, kind, tags and last flag; false when [id] is unknown.
  Future<bool> update(int id, MealDraft draft);

  /// Names [name] as the photo of [id], whose file must already exist; false
  /// when [id] is unknown, throws when another row holds [name].
  Future<bool> attachPhoto(int id, String name);

  Future<Meal?> delete(int id);

  /// The meals whose food day is in [from, to], oldest wall clock first.
  Future<List<Meal>> between(LocalDate from, LocalDate to);

  Future<int> count();

  Future<int> clear();

  /// Releases the photos of meals taken before [cutoff], keeping the rows;
  /// returns the released names, oldest first.
  Future<List<String>> deletePhotosBefore(DateTime cutoff);
}
