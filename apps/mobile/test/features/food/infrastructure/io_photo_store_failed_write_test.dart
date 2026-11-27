import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/infrastructure/io_photo_store.dart';

final _photo = Uint8List.fromList(List.filled(4096, 7));

void main() {
  late Directory root;
  late IoPhotoStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meal_photos_full_');
    addTearDown(() => root.delete(recursive: true));
    store = IoPhotoStore(() async => root);
  });

  bool exists(String name) =>
      FileSystemEntity.typeSync('${root.path}/$name', followLinks: false) !=
      FileSystemEntityType.notFound;

  group('criterion 6: a failed photo write leaves no .tmp file', () {
    // /dev/full fails every write with ENOSPC, the errno D5 reads as noSpace.
    test('a full disk throws errno 28 and leaves no .tmp', () async {
      Link('${root.path}/a.jpg.tmp').createSync('/dev/full');

      await expectLater(
        () => store.save('a.jpg', _photo),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.osError?.errorCode,
            'errno',
            28,
          ),
        ),
      );

      expect(exists('a.jpg.tmp'), isFalse, reason: 'the .tmp is left behind');
      expect(exists('a.jpg'), isFalse);
    });

    test('a failed rename throws and leaves no .tmp', () async {
      Directory('${root.path}/a.jpg').createSync();

      await expectLater(
        () => store.save('a.jpg', _photo),
        throwsA(isA<FileSystemException>()),
      );

      expect(exists('a.jpg.tmp'), isFalse, reason: 'the .tmp is left behind');
    });

    test('after a failed rename the store counts no bytes', () async {
      Directory('${root.path}/a.jpg').createSync();

      await expectLater(
        () => store.save('a.jpg', _photo),
        throwsA(isA<FileSystemException>()),
      );

      expect(await store.totalBytes(), 0);
    });
  });
}
