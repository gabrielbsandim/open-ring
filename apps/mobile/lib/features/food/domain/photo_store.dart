import 'dart:typed_data';

final _photoName = RegExp(r'^[A-Za-z0-9_-]{1,80}\.jpg$');

bool isMealPhotoName(String name) => _photoName.hasMatch(name);

void checkMealPhotoName(String name) {
  if (isMealPhotoName(name)) return;
  throw ArgumentError.value(name, 'name', 'not a meal photo name');
}

abstract interface class PhotoStore {
  Future<void> save(String name, Uint8List bytes);

  Future<Uint8List?> read(String name);

  Future<bool> delete(String name);

  /// Removes every file in the store and returns how many.
  Future<int> deleteAll();

  /// Size in bytes of each valid meal photo file currently stored.
  Future<Map<String, int>> fileBytes();

  Future<int> totalBytes();
}

final class InMemoryPhotoStore implements PhotoStore {
  final Map<String, Uint8List> _photos = {};

  @override
  Future<void> save(String name, Uint8List bytes) async {
    checkMealPhotoName(name);
    _photos[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> read(String name) async {
    checkMealPhotoName(name);
    return _photos[name];
  }

  @override
  Future<bool> delete(String name) async {
    checkMealPhotoName(name);
    return _photos.remove(name) != null;
  }

  @override
  Future<int> deleteAll() async {
    final removed = _photos.length;
    _photos.clear();
    return removed;
  }

  @override
  Future<Map<String, int>> fileBytes() async => {
    for (final entry in _photos.entries) entry.key: entry.value.length,
  };

  @override
  Future<int> totalBytes() async =>
      _photos.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
}
