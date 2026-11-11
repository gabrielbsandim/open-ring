import 'dart:math' as math;

import 'package:meta/meta.dart';

const earthMeanRadiusMeters = 6371008.8;

@immutable
final class TrackPoint {
  new({
    required this.at,
    required this.latitude,
    required this.longitude,
    this.elevationMeters,
    this.heartRateBpm,
    this.accuracyMeters,
  }) {
    if (!validLatitude(latitude)) {
      throw RangeError.value(latitude, 'latitude', 'must be in [-90, 90]');
    }
    if (!validLongitude(longitude)) {
      throw RangeError.value(longitude, 'longitude', 'must be in [-180, 180)');
    }
  }

  final DateTime at;
  final double latitude;
  final double longitude;
  final double? elevationMeters;
  final int? heartRateBpm;
  final double? accuracyMeters;

  static bool validLatitude(double value) =>
      value.isFinite && value >= -90 && value <= 90;

  static bool validLongitude(double value) =>
      value.isFinite && value >= -180 && value < 180;
}

double haversineMeters(TrackPoint a, TrackPoint b) {
  final lat1 = _radians(a.latitude);
  final lat2 = _radians(b.latitude);
  final halfLat = math.sin((lat2 - lat1) / 2);
  final halfLon = math.sin(_radians(b.longitude - a.longitude) / 2);
  final h =
      halfLat * halfLat + math.cos(lat1) * math.cos(lat2) * halfLon * halfLon;
  return 2 * earthMeanRadiusMeters * math.asin(math.sqrt(math.min(1, h)));
}

double _radians(double degrees) => degrees * math.pi / 180;

@immutable
final class WorkoutRoute {
  new({
    required Iterable<Iterable<TrackPoint>> segments,
    this.name,
    this.activityType,
  }) : segments = List.unmodifiable([
         for (final segment in segments)
           if (segment.isNotEmpty)
             List<TrackPoint>.unmodifiable(_byTime(segment)),
       ]);

  final String? name;
  final String? activityType;
  final List<List<TrackPoint>> segments;

  bool get isEmpty => segments.isEmpty;

  Iterable<TrackPoint> get points => segments.expand((segment) => segment);

  // Gaps between segments are pauses, so they add no distance.
  double get distanceMeters {
    var total = 0.0;
    for (final segment in segments) {
      for (var i = 1; i < segment.length; i++) {
        total += haversineMeters(segment[i - 1], segment[i]);
      }
    }
    return total;
  }

  static List<TrackPoint> _byTime(Iterable<TrackPoint> points) =>
      points.toList()..sort((a, b) => a.at.compareTo(b.at));
}
