import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_ring/features/food/infrastructure/image_picker_meal_camera.dart';

const _uuid = '0f8e2a4c-1b3d-4e5f-8a9b-0c1d2e3f4a5b';

typedef _Pick = ({
  ImageSource source,
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
});

final class _FakePicker extends Fake implements ImagePicker {
  XFile? picked;
  LostDataResponse lost = LostDataResponse.empty();
  final picks = <_Pick>[];

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    picks.add((
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    ));
    return picked;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async => lost;
}

void main() {
  late Directory dir;
  late _FakePicker picker;
  late ImagePickerMealCamera camera;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meal_camera_');
    addTearDown(() => dir.delete(recursive: true));
    picker = _FakePicker();
    camera = ImagePickerMealCamera(picker, cache: () async => dir);
  });

  File pickedFile(List<int> bytes) =>
      File('${dir.path}/image_picker_1.jpg')..writeAsBytesSync(bytes);

  group('D1: takePhoto', () {
    test('asks the camera at 1024 px and quality 85', () async {
      await camera.takePhoto();

      expect(picker.picks, [
        (
          source: ImageSource.camera,
          maxWidth: 1024.0,
          maxHeight: 1024.0,
          imageQuality: 85,
        ),
      ]);
    });

    test('returns the bytes and deletes the returned file', () async {
      final file = pickedFile([0xFF, 0xD8, 1, 2, 0xFF, 0xD9]);
      picker.picked = XFile(file.path);

      final bytes = await camera.takePhoto();

      expect(bytes, Uint8List.fromList([0xFF, 0xD8, 1, 2, 0xFF, 0xD9]));
      expect(file.existsSync(), isFalse, reason: 'the picker copy is kept');
    });

    test('a cancelled capture gives null', () async {
      expect(await camera.takePhoto(), isNull);
    });
  });

  group('D6: retrieveLost', () {
    test('returns the lost bytes and deletes the file', () async {
      final file = pickedFile([0xFF, 0xD8, 9, 0xFF, 0xD9]);
      picker.lost = LostDataResponse(
        file: XFile(file.path),
        type: RetrieveType.image,
      );

      final bytes = await camera.retrieveLost();

      expect(bytes, Uint8List.fromList([0xFF, 0xD8, 9, 0xFF, 0xD9]));
      expect(file.existsSync(), isFalse, reason: 'the picker copy is kept');
    });

    test('nothing lost gives null', () async {
      expect(await camera.retrieveLost(), isNull);
    });

    test('deletes the full size original the plugin kept', () async {
      final original = File('${dir.path}/$_uuid-123456789.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 7, 0xFF, 0xD9]);
      final scaled = File('${dir.path}/scaled_$_uuid-123456789.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 9, 0xFF, 0xD9]);
      picker.lost = LostDataResponse(
        file: XFile(scaled.path),
        type: RetrieveType.image,
      );

      final bytes = await camera.retrieveLost();

      expect(bytes, Uint8List.fromList([0xFF, 0xD8, 9, 0xFF, 0xD9]));
      expect(original.existsSync(), isFalse, reason: 'GPS outlives recovery');
    });

    test('with nothing lost it still deletes a kept original', () async {
      final original = File('${dir.path}/${_uuid}42.jpg')
        ..writeAsBytesSync([1]);

      expect(await camera.retrieveLost(), isNull);
      expect(original.existsSync(), isFalse);
    });
  });

  group('D6: sweepPickerOriginals', () {
    test('deletes only picker originals and their scaled copies', () async {
      final doomed = [
        '${_uuid}42.jpg',
        '$_uuid-42.jpg',
        'scaled_${_uuid}42.jpg',
      ];
      final kept = [
        'image_picker_1.jpg',
        'meal_1_0a1b2c3d.jpg',
        '${_uuid}42.mp4',
        '${_uuid}42.jpg.tmp',
        'x$_uuid.jpg',
      ];
      for (final name in [...doomed, ...kept]) {
        File('${dir.path}/$name').writeAsBytesSync([1]);
      }
      Directory('${dir.path}/$_uuid').createSync();

      final removed = await sweepPickerOriginals(dir);

      expect(removed, doomed.length);
      final left = [
        for (final entry in dir.listSync())
          entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
      ];
      expect(left, unorderedEquals([...kept, _uuid]));
    });

    test('a missing cache folder deletes nothing', () async {
      expect(await sweepPickerOriginals(Directory('${dir.path}/none')), 0);
    });
  });
}
