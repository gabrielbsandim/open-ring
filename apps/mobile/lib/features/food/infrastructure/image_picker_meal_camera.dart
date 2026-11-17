import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:path_provider/path_provider.dart';

// The plugin names a camera original File.createTempFile(uuid, ".jpg") in the
// cache dir, and its resized copy "scaled_" plus that name.
final _pickerOriginal = RegExp(
  r'^(scaled_)?[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}-?\d+\.jpg$',
);

/// Deletes the camera originals the picker left in [cache] and returns how
/// many; other files and folders are kept.
Future<int> sweepPickerOriginals(Directory cache) async {
  if (!cache.existsSync()) return 0;
  final originals = await cache
      .list()
      .where((entry) => entry is File)
      .cast<File>()
      .where((file) => _pickerOriginal.hasMatch(file.uri.pathSegments.last))
      .toList();
  for (final file in originals) {
    await file.delete();
  }
  return originals.length;
}

final class ImagePickerMealCamera implements MealCamera {
  new(this._picker, {Future<Directory> Function()? cache})
    : _cache = cache ?? getTemporaryDirectory;

  final ImagePicker _picker;
  final Future<Directory> Function() _cache;

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

  // After process death the plugin keeps the GPS original next to the copy it
  // returns; with nothing lost yet a pending capture may still need its own.
  @override
  Future<Uint8List?> retrieveLost() async {
    final response = await _picker.retrieveLostData();
    final file = response.file;
    if (file == null) return null;
    final bytes = await _consume(file);
    await _sweep();
    return bytes;
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

  // A file that cannot be deleted now is swept at the next start, and the
  // recovered photo must not be lost for it.
  Future<void> _sweep() async {
    try {
      await sweepPickerOriginals(await _cache());
    } on FileSystemException {
      return;
    }
  }

  Future<void> _delete(File file) async {
    if (!file.existsSync()) return;
    await file.delete();
  }
}
