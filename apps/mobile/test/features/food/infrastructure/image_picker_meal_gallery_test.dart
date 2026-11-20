import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:open_ring/features/food/domain/meal_gallery.dart';
import 'package:open_ring/features/food/infrastructure/image_picker_meal_gallery.dart';

const _uuid = '0f8e2a4c-1b3d-4e5f-8a9b-0c1d2e3f4a5b';
const _uuidTwo = 'a1b2c3d4-e5f6-4789-abcd-0123456789ef';

typedef _MultiPick = ({
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
  int? limit,
  bool requestFullMetadata,
});

final class _FakePlatform extends Fake implements ImagePickerPlatform;

final class _FakePicker extends Fake implements ImagePicker {
  List<XFile> picked = const [];
  final picks = <_MultiPick>[];

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    picks.add((
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
      limit: limit,
      requestFullMetadata: requestFullMetadata,
    ));
    return picked;
  }
}

void main() {
  late Directory dir;
  late _FakePicker picker;
  late ImagePickerMealGallery gallery;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meal_gallery_');
    addTearDown(() => dir.delete(recursive: true));
    picker = _FakePicker();
    gallery = ImagePickerMealGallery(picker, cache: () async => dir);
  });

  File writeFile(String relativePath, List<int> bytes) {
    final file = File('${dir.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('configureAndroidPhotoPicker', () {
    test('enables useAndroidPhotoPicker on ImagePickerAndroid', () {
      final android = ImagePickerAndroid();
      expect(android.useAndroidPhotoPicker, isFalse);

      configureAndroidPhotoPicker(android);

      expect(android.useAndroidPhotoPicker, isTrue);
    });

    test('enables useAndroidPhotoPicker on ImagePickerPlatform.instance by default', () {
      final previous = ImagePickerPlatform.instance;
      final android = ImagePickerAndroid();
      ImagePickerPlatform.instance = android;
      addTearDown(() => ImagePickerPlatform.instance = previous);

      configureAndroidPhotoPicker();

      expect(android.useAndroidPhotoPicker, isTrue);
    });

    test('is a no-op on non-Android ImagePickerPlatform', () {
      final other = _FakePlatform();

      expect(() => configureAndroidPhotoPicker(other), returnsNormally);
    });
  });

  group('ImagePickerMealGallery.pickPhotos', () {
    test(
      'passes maxWidth 1024, maxHeight 1024, imageQuality 85, and limit 20',
      () async {
        await gallery.pickPhotos();

        expect(galleryPickLimit, 20);
        expect(picker.picks, [
          (
            maxWidth: 1024.0,
            maxHeight: 1024.0,
            imageQuality: 85,
            limit: 20,
            requestFullMetadata: true,
          ),
        ]);
      },
    );

    test('passes custom limit to pickMultiImage', () async {
      await gallery.pickPhotos(limit: 5);

      expect(picker.picks.single.limit, 5);
    });

    test('empty pick returns empty list', () async {
      expect(await gallery.pickPhotos(), isEmpty);
    });

    test(
      'returns photo bytes, deletes every returned file, and sweeps cache',
      () async {
        final first = writeFile('picked_1.jpg', [0xFF, 0xD8, 1, 0xFF, 0xD9]);
        final second = writeFile('picked_2.jpg', [0xFF, 0xD8, 2, 0xFF, 0xD9]);
        final cached = writeFile('$_uuid/original.jpg', [1, 2, 3]);
        final scaled = writeFile('scaled_${_uuid}_1.jpg', [4, 5, 6]);
        final kept = writeFile('meal_1_0a1b2c3d.jpg', [7, 8, 9]);
        picker.picked = [XFile(first.path), XFile(second.path)];

        final photos = await gallery.pickPhotos();

        expect(photos, [
          Uint8List.fromList([0xFF, 0xD8, 1, 0xFF, 0xD9]),
          Uint8List.fromList([0xFF, 0xD8, 2, 0xFF, 0xD9]),
        ]);
        expect(first.existsSync(), isFalse);
        expect(second.existsSync(), isFalse);
        expect(cached.parent.existsSync(), isFalse);
        expect(scaled.existsSync(), isFalse);
        expect(kept.existsSync(), isTrue);
      },
    );

    test(
      'boundary: reads at most limit photos and deletes every file past limit',
      () async {
        final files = [
          for (var i = 1; i <= 4; i++)
            writeFile('picked_$i.jpg', [0xFF, 0xD8, i, 0xFF, 0xD9]),
        ];
        picker.picked = [for (final f in files) XFile(f.path)];

        final photos = await gallery.pickPhotos(limit: 2);

        expect(photos, [
          Uint8List.fromList([0xFF, 0xD8, 1, 0xFF, 0xD9]),
          Uint8List.fromList([0xFF, 0xD8, 2, 0xFF, 0xD9]),
        ]);
        for (final file in files) {
          expect(
            file.existsSync(),
            isFalse,
            reason: 'every returned file must be deleted, even past limit',
          );
        }
      },
    );

    test('error path: partial read failure still deletes remaining files and sweeps cache', () async {
      final first = writeFile('picked_1.jpg', [0xFF, 0xD8, 1, 0xFF, 0xD9]);
      final missing = File('${dir.path}/picked_missing.jpg');
      final third = writeFile('picked_3.jpg', [0xFF, 0xD8, 3, 0xFF, 0xD9]);
      final uuidDir = Directory('${dir.path}/$_uuid')..createSync();
      writeFile('$_uuid/original.jpg', [1, 2, 3]);
      final scaled = writeFile('scaled_${_uuid}_1.jpg', [4, 5, 6]);
      picker.picked = [
        XFile(first.path),
        XFile(missing.path),
        XFile(third.path),
      ];

      await expectLater(gallery.pickPhotos(), throwsA(isA<Exception>()));

      expect(first.existsSync(), isFalse);
      expect(third.existsSync(), isFalse);
      expect(uuidDir.existsSync(), isFalse);
      expect(scaled.existsSync(), isFalse);
    });
  });

  group('sweepGalleryPickerCache', () {
    test('returns 0 when cache directory is missing', () async {
      final missing = Directory('${dir.path}/none');

      expect(await sweepGalleryPickerCache(missing), 0);
    });

    test('deletes uuid subdirectories recursively and top-level scaled_ files, '
        'keeping unrelated files and non-uuid directories', () async {
      writeFile('$_uuid/photo1.jpg', [1]);
      writeFile('$_uuid/nested/photo2.jpg', [2]);
      final uuidOne = Directory('${dir.path}/$_uuid');
      final uuidTwo = Directory('${dir.path}/$_uuidTwo')..createSync();
      final scaled = writeFile('scaled_${_uuid}42.jpg', [3]);
      final keptFiles = [
        writeFile('meal_1_0a1b2c3d.jpg', [4]),
        writeFile('image_picker_1.jpg', [5]),
        writeFile('notes.txt', [6]),
      ];
      final keptDir = writeFile('flutter_assets/asset.bin', [7]).parent;
      final nonUuidDir = writeFile('x$_uuid/photo.jpg', [8]).parent;

      final removed = await sweepGalleryPickerCache(dir);

      expect(removed, 3);
      expect(uuidOne.existsSync(), isFalse);
      expect(uuidTwo.existsSync(), isFalse);
      expect(scaled.existsSync(), isFalse);
      for (final file in keptFiles) {
        expect(file.existsSync(), isTrue);
      }
      expect(keptDir.existsSync(), isTrue);
      expect(nonUuidDir.existsSync(), isTrue);
    });
  });
}
