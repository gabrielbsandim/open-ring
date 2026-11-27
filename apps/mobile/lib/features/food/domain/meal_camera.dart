import 'dart:typed_data';

abstract interface class MealCamera {
  /// The bytes of a new photo, null when the capture is cancelled.
  Future<Uint8List?> takePhoto();

  /// A photo taken while Android killed the app, null when there is none.
  Future<Uint8List?> retrieveLost();
}

final class FakeMealCamera implements MealCamera {
  new({this.photo, this.lost});

  Uint8List? photo;

  /// Handed out once, as the platform clears what it returns.
  Uint8List? lost;

  @override
  Future<Uint8List?> takePhoto() async => photo;

  @override
  Future<Uint8List?> retrieveLost() async {
    final found = lost;
    lost = null;
    return found;
  }
}
