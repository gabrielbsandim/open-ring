import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';

/// What the Food tables and photo folder hold on this phone.
@immutable
final class FoodDataCount {
  const new({
    required this.meals,
    required this.photos,
    required this.photoBytes,
  });

  final int meals;
  final int photos;
  final int photoBytes;

  bool get hasData => meals > 0 || photos > 0 || photoBytes > 0;

  @override
  bool operator ==(Object other) =>
      other is FoodDataCount &&
      other.meals == meals &&
      other.photos == photos &&
      other.photoBytes == photoBytes;

  @override
  int get hashCode => Object.hash(meals, photos, photoBytes);
}

// Not gated on the module: data kept while Food is off can still be deleted.
final foodDataCountProvider = FutureProvider<FoodDataCount>((ref) async {
  ref.watch(dataRevisionProvider);
  final meals = ref.watch(mealStoreProvider);
  final photos = ref.watch(photoStoreProvider);
  final refs = await meals.photoRefs();
  return FoodDataCount(
    meals: await meals.count(),
    photos: refs.length,
    photoBytes: await photos.totalBytes(),
  );
});

final foodDataEraserProvider = Provider<FoodDataEraser>(FoodDataEraser.new);

class FoodDataEraser {
  const new(this._ref);

  final Ref _ref;

  /// Clears meals in the database first, then empties the photo folder and
  /// bumps revision whenever the database was cleared so UI stays accurate.
  Future<bool> clear() async {
    try {
      await _ref.read(mealStoreProvider).clear();
    } on Object catch (error) {
      debugPrint('Food meal rows were not deleted: $error');
      return false;
    }
    var photosCleared = true;
    try {
      await _ref.read(photoStoreProvider).deleteAll();
    } on Object catch (error) {
      debugPrint('Food photo files were not deleted: $error');
      photosCleared = false;
    }
    if (_ref.mounted) _ref.read(dataRevisionProvider.notifier).bump();
    return photosCleared;
  }
}
