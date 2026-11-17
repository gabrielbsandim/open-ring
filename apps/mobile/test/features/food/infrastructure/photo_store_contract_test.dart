import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/infrastructure/io_photo_store.dart';

const _badNames = ['../a.jpg', '/data/a.jpg', 'a/b.jpg', '', 'a.png'];

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

Future<Directory> _tempDir() async {
  final dir = await Directory.systemTemp.createTemp('meal_photos_');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  final stores = <String, Future<PhotoStore> Function()>{
    'InMemoryPhotoStore': () async => InMemoryPhotoStore(),
    'IoPhotoStore': () async {
      final dir = await _tempDir();
      return IoPhotoStore(() async => dir);
    },
  };

  for (final MapEntry(key: name, value: create) in stores.entries) {
    group('criterion 11: photo store contract on $name', () {
      late PhotoStore store;

      setUp(() async => store = await create());

      test('save then read returns equal bytes', () async {
        await store.save('a.jpg', _bytes([0, 1, 2, 255]));

        expect(await store.read('a.jpg'), _bytes([0, 1, 2, 255]));
      });

      test('an empty photo reads back empty, not missing', () async {
        await store.save('a.jpg', Uint8List(0));

        expect(await store.read('a.jpg'), isEmpty);
      });

      test('save again overwrites', () async {
        await store.save('a.jpg', _bytes([1, 2, 3]));
        await store.save('a.jpg', _bytes([9]));

        expect(await store.read('a.jpg'), _bytes([9]));
        expect(await store.totalBytes(), 1);
      });

      test('read of a missing name is null', () async {
        expect(await store.read('a.jpg'), isNull);
      });

      test('delete of a missing name is false', () async {
        expect(await store.delete('a.jpg'), isFalse);
      });

      test('delete of a saved name is true and it reads back null', () async {
        await store.save('a.jpg', _bytes([1]));
        await store.save('b.jpg', _bytes([2]));

        expect(await store.delete('a.jpg'), isTrue);
        expect(await store.read('a.jpg'), isNull);
        expect(await store.read('b.jpg'), _bytes([2]));
      });

      test('totalBytes is the sum of the saved photos', () async {
        expect(await store.totalBytes(), 0);

        await store.save('a.jpg', _bytes([1, 2, 3]));
        await store.save('b.jpg', _bytes([4, 5, 6, 7, 8]));

        expect(await store.totalBytes(), 8);
      });

      test('deleteAll returns the count and leaves nothing', () async {
        await store.save('a.jpg', _bytes([1, 2, 3]));
        await store.save('b.jpg', _bytes([4, 5]));

        expect(await store.deleteAll(), 2);
        expect(await store.totalBytes(), 0);
        expect(await store.read('a.jpg'), isNull);
      });

      test('deleteAll before any save returns 0', () async {
        expect(await store.deleteAll(), 0);
      });

      for (final bad in _badNames) {
        test('every named method throws ArgumentError on "$bad"', () async {
          await expectLater(
            () => store.save(bad, _bytes([1])),
            throwsArgumentError,
          );
          await expectLater(() => store.read(bad), throwsArgumentError);
          await expectLater(() => store.delete(bad), throwsArgumentError);
          expect(await store.totalBytes(), 0);
        });
      }
    });
  }
}
