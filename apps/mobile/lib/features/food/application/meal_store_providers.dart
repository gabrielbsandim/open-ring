import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';

// A forgotten override must fail loudly, not keep photos in memory.
final mealStoreProvider = Provider<MealStore>(
  (ref) => throw UnimplementedError('Override mealStoreProvider.'),
);

final photoStoreProvider = Provider<PhotoStore>(
  (ref) => throw UnimplementedError('Override photoStoreProvider.'),
);
