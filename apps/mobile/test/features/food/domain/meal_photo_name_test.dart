import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';

void main() {
  group('isMealPhotoName accepts a bare .jpg name', () {
    for (final name in [
      'a.jpg',
      'Meal_2026-12-01_0830.jpg',
      '${'x' * 80}.jpg',
    ]) {
      test(name, () => expect(isMealPhotoName(name), isTrue));
    }
  });

  group('isMealPhotoName refuses anything else', () {
    for (final name in [
      '../a.jpg',
      '/data/a.jpg',
      'a/b.jpg',
      r'a\b.jpg',
      '',
      'a.png',
      '.jpg',
      '${'x' * 81}.jpg',
      'a.JPG',
      'a.jpeg',
      'a.jpg.tmp',
      'a b.jpg',
      'a.jpg\n',
      'a..jpg',
    ]) {
      test('"$name"', () => expect(isMealPhotoName(name), isFalse));
    }
  });
}
