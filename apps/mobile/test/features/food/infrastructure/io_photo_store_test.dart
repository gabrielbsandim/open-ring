import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/infrastructure/io_photo_store.dart';

void main() {
  late Directory parent;
  late Directory root;
  late IoPhotoStore store;

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('meal_photos_parent_');
    addTearDown(() => parent.delete(recursive: true));
    root = Directory('${parent.path}/meal_photos');
    store = IoPhotoStore(() async => root);
  });

  List<String> namesIn(Directory dir) => [
    for (final entity in dir.listSync()) entity.uri.pathSegments.last,
  ];

  group('criterion 12: IoPhotoStore on disk', () {
    test('save writes <root>/a.jpg and leaves no .tmp', () async {
      await store.save('a.jpg', Uint8List.fromList([1, 2, 3]));

      expect(File('${root.path}/a.jpg').readAsBytesSync(), [1, 2, 3]);
      expect(namesIn(root), ['a.jpg']);
    });

    test('a leftover .tmp counts in totalBytes', () async {
      await store.save('a.jpg', Uint8List.fromList([1, 2, 3]));
      File('${root.path}/x.jpg.tmp').writeAsBytesSync([4, 5]);

      expect(await store.totalBytes(), 5);
    });

    test('deleteAll removes a leftover .tmp too', () async {
      await store.save('a.jpg', Uint8List.fromList([1, 2, 3]));
      File('${root.path}/x.jpg.tmp').writeAsBytesSync([4, 5]);

      expect(await store.deleteAll(), 2);
      expect(namesIn(root), isEmpty);
      expect(await store.totalBytes(), 0);
    });

    test('a file in the parent of root survives deleteAll', () async {
      final outside = File('${parent.path}/keep.jpg')..writeAsBytesSync([7]);
      await store.save('a.jpg', Uint8List.fromList([1]));

      await store.deleteAll();

      expect(outside.existsSync(), isTrue);
    });

    test('a name that climbs out of root writes nothing outside it', () async {
      await expectLater(
        () => store.save('../a.jpg', Uint8List.fromList([1])),
        throwsArgumentError,
      );

      expect(File('${parent.path}/a.jpg').existsSync(), isFalse);
    });
  });

  group('D8: the root is created on first save', () {
    test('before any save, nothing fails and nothing is there', () async {
      expect(await store.read('a.jpg'), isNull);
      expect(await store.delete('a.jpg'), isFalse);
      expect(await store.totalBytes(), 0);
      expect(await store.deleteAll(), 0);
    });

    test('the first save creates the folder', () async {
      await store.save('a.jpg', Uint8List.fromList([1]));

      expect(root.existsSync(), isTrue);
      expect(await store.read('a.jpg'), [1]);
    });
  });
}
