import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:open_ring/features/food/domain/meal_gallery.dart';
import 'package:path_provider/path_provider.dart';

final _uuidDir = RegExp(
  r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Enables Android's Photo Picker so picking needs no storage permission.
void configureAndroidPhotoPicker([ImagePickerPlatform? platform]) {
  final target = platform ?? ImagePickerPlatform.instance;
  if (target is ImagePickerAndroid) target.useAndroidPhotoPicker = true;
}

/// Removes UUID folders and `scaled_` copies left by the gallery picker.
Future<int> sweepGalleryPickerCache(Directory cache) async {
  if (!cache.existsSync()) return 0;
  var removed = 0;
  final entries = await cache.list().toList();
  for (final entry in entries) {
    if (await _sweepEntry(entry)) removed++;
  }
  return removed;
}

Future<bool> _sweepEntry(FileSystemEntity entry) async {
  final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  if (name == null) return false;
  try {
    if (entry is Directory && _uuidDir.hasMatch(name)) {
      await entry.delete(recursive: true);
      return true;
    }
    if (entry is File && name.startsWith('scaled_')) {
      await entry.delete();
      return true;
    }
  } on FileSystemException {
    return false;
  }
  return false;
}

final class ImagePickerMealGallery implements MealGallery {
  new(this._picker, {Future<Directory> Function()? cache})
    : _cache = cache ?? getTemporaryDirectory;

  final ImagePicker _picker;
  final Future<Directory> Function() _cache;

  @override
  Future<List<Uint8List>> pickPhotos({int limit = galleryPickLimit}) async {
    final files = await _picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
      limit: limit,
    );
    if (files.isEmpty) return const [];
    try {
      final bytes = <Uint8List>[];
      for (final file in files.take(limit)) {
        bytes.add(await file.readAsBytes());
      }
      return bytes;
    } finally {
      for (final file in files) {
        await _deleteQuietly(File(file.path));
      }
      await _sweep();
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (!file.existsSync()) return;
      await file.delete();
    } on FileSystemException {
      return;
    }
  }

  Future<void> _sweep() async {
    try {
      await sweepGalleryPickerCache(await _cache());
    } on FileSystemException {
      return;
    }
  }
}
