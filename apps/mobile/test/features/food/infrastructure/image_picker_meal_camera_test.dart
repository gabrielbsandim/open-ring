import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_ring/features/food/infrastructure/image_picker_meal_camera.dart';

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
    camera = ImagePickerMealCamera(picker);
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
  });
}
