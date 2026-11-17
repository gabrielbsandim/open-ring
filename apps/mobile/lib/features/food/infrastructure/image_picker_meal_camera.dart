import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';

final class ImagePickerMealCamera implements MealCamera {
  new(this._picker);

  final ImagePicker _picker;

  @override
  Future<Uint8List?> takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    return await _consume(file);
  }

  @override
  Future<Uint8List?> retrieveLost() async {
    final response = await _picker.retrieveLostData();
    return await _consume(response.file);
  }

  // The picker copy still holds GPS, so it never outlives the read.
  Future<Uint8List?> _consume(XFile? file) async {
    if (file == null) return null;
    try {
      return await file.readAsBytes();
    } finally {
      await _delete(File(file.path));
    }
  }

  Future<void> _delete(File file) async {
    if (!file.existsSync()) return;
    await file.delete();
  }
}
