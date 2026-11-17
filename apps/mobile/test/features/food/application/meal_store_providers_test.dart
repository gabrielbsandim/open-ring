import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';

// Riverpod may wrap what a provider throws, so either form counts.
final Matcher _unimplemented = predicate<Object>(
  (error) =>
      error is UnimplementedError ||
      (error is ProviderException && error.exception is UnimplementedError),
  'UnimplementedError',
);

void main() {
  group('D7: the stores fail loudly when not overridden', () {
    test('mealStoreProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(mealStoreProvider), throwsA(_unimplemented));
    });

    test('photoStoreProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(photoStoreProvider), throwsA(_unimplemented));
    });
  });
}
