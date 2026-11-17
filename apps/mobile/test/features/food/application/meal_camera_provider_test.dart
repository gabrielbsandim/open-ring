import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';

void main() {
  test('Interface: mealCameraProvider fails loudly when not overridden', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(() => container.read(mealCameraProvider), throwsA(anything));
  });
}
