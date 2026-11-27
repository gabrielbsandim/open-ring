import 'dart:typed_data';

const galleryPickLimit = 20;

abstract interface class MealGallery {
  /// Returns up to [limit] picked photos as bytes, empty when cancelled.
  Future<List<Uint8List>> pickPhotos({int limit = galleryPickLimit});
}

final class FakeMealGallery implements MealGallery {
  new({this.photos = const [], this.error});

  List<Uint8List> photos;
  Object? error;
  int calls = 0;
  int? lastLimit;

  @override
  Future<List<Uint8List>> pickPhotos({int limit = galleryPickLimit}) async {
    calls++;
    lastLimit = limit;
    final failure = error;
    if (failure != null) Error.throwWithStackTrace(failure, StackTrace.current);
    return photos.take(limit).toList();
  }
}
