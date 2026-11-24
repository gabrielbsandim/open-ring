import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:meta/meta.dart';

const int aiWirePhotoLongEdge = 768;
const int aiWirePhotoQuality = 70;

/// The bytes sent for one meal photo. They are never stored; only the hash,
/// the size and the byte count are kept.
@immutable
final class WirePhoto {
  const new({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sha256,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// Lowercase hex SHA-256 of [bytes].
  final String sha256;

  int get shortEdge => width < height ? width : height;
}

/// Decodes a stored meal photo and re-encodes it for the wire: orientation in
/// the pixels, long edge at most [aiWirePhotoLongEdge], and no metadata.
/// Throws [FormatException] when [stored] is not a JPEG. Costs about 4 MB and
/// up to a second on a 1024 px photo, so callers run it in `Isolate.run`.
WirePhoto prepareWirePhoto(Uint8List stored) {
  final decoded = _decode(stored);
  if (decoded == null) throw const FormatException('Not a JPEG photo.');
  final clean = _fitLongEdge(img.bakeOrientation(decoded))
    // The encoder writes APP1 from exif and APP2 from the ICC profile.
    ..exif = img.ExifData()
    ..iccProfile = null
    ..textData = null;
  final bytes = img.encodeJpg(clean, quality: aiWirePhotoQuality);
  return WirePhoto(
    bytes: bytes,
    width: clean.width,
    height: clean.height,
    sha256: sha256.convert(bytes).toString(),
  );
}

img.Image? _decode(Uint8List stored) {
  try {
    return img.decodeJpg(stored);
  } on img.ImageException {
    return null;
  }
}

img.Image _fitLongEdge(img.Image upright) {
  final landscape = upright.width >= upright.height;
  final longEdge = landscape ? upright.width : upright.height;
  if (longEdge <= aiWirePhotoLongEdge) return upright;
  return img.copyResize(
    upright,
    width: landscape ? aiWirePhotoLongEdge : null,
    height: landscape ? null : aiWirePhotoLongEdge,
    interpolation: img.Interpolation.average,
  );
}
