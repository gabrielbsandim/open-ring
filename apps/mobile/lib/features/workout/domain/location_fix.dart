import 'package:meta/meta.dart';

@immutable
final class LocationFix {
  const new({
    required this.at,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.altitudeMeters,
  });

  final DateTime at;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? altitudeMeters;
}
