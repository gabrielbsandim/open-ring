import 'dart:io';
import 'dart:typed_data';

import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:path_provider/path_provider.dart';

final class IoPhotoStore implements PhotoStore {
  new(this._root);

  factory documents() => IoPhotoStore(() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/meal_photos');
  });

  final Future<Directory> Function() _root;

  // Written under a temporary name and renamed, so a killed app never leaves
  // half a photo under its final name.
  @override
  Future<void> save(String name, Uint8List bytes) async {
    checkMealPhotoName(name);
    final root = await _root();
    await root.create(recursive: true);
    final temporary = File('${root.path}/$name.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename('${root.path}/$name');
  }

  @override
  Future<Uint8List?> read(String name) async {
    final file = await _file(name);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  }

  @override
  Future<bool> delete(String name) async {
    final file = await _file(name);
    if (!file.existsSync()) return false;
    await file.delete();
    return true;
  }

  @override
  Future<int> deleteAll() async {
    final files = await _files();
    for (final file in files) {
      await file.delete();
    }
    return files.length;
  }

  @override
  Future<int> totalBytes() async {
    var total = 0;
    for (final file in await _files()) {
      total += await file.length();
    }
    return total;
  }

  Future<File> _file(String name) async {
    checkMealPhotoName(name);
    final root = await _root();
    return File('${root.path}/$name');
  }

  Future<List<File>> _files() async {
    final root = await _root();
    if (!root.existsSync()) return const [];
    return await root
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
  }
}
