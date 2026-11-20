import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_gallery.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';

// A forgotten override must fail loudly, not keep photos in memory.
final mealStoreProvider = Provider<MealStore>(
  (ref) => throw UnimplementedError('Override mealStoreProvider.'),
);

final photoStoreProvider = Provider<PhotoStore>(
  (ref) => throw UnimplementedError('Override photoStoreProvider.'),
);

final mealCameraProvider = Provider<MealCamera>(
  (ref) => throw UnimplementedError('Override mealCameraProvider.'),
);

final mealGalleryProvider = Provider<MealGallery>(
  (ref) => throw UnimplementedError('Override mealGalleryProvider.'),
);

final mealPhotoSaverProvider = Provider<MealPhotoSaver>(
  (ref) => MealPhotoSaver(
    ref.watch(mealStoreProvider),
    ref.watch(photoStoreProvider),
    now: ref.watch(clockProvider),
  ),
);
