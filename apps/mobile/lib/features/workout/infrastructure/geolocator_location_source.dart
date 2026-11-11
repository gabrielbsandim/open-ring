import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:open_ring/features/workout/domain/location_fix.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';

final class GeolocatorLocationSource implements LocationSource {
  new({GeolocatorPlatform? platform, this.platformType})
    : _platform = platform ?? GeolocatorPlatform.instance;

  final GeolocatorPlatform _platform;
  final TargetPlatform? platformType;

  @override
  Stream<LocationFix> fixes(LocationNotice notice) async* {
    await _ensureAccess();
    yield* _platform
        .getPositionStream(locationSettings: settings(notice))
        .map(fixOf);
  }

  LocationSettings settings(LocationNotice notice) =>
      switch (platformType ?? defaultTargetPlatform) {
        TargetPlatform.android => AndroidSettings(
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: notice.title,
            notificationText: notice.text,
            notificationChannelName: notice.channel,
            notificationIcon: const AndroidResource(name: 'ic_notification'),
            setOngoing: true,
            enableWakeLock: true,
          ),
        ),
        TargetPlatform.iOS => AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.fitness,
          showBackgroundLocationIndicator: true,
        ),
        _ => const LocationSettings(),
      };

  static LocationFix fixOf(Position position) => LocationFix(
    at: position.timestamp,
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.hasAccuracy ? position.accuracy : double.infinity,
    altitudeMeters: position.hasAltitude ? position.altitude : null,
  );

  Future<void> _ensureAccess() async {
    if (!await _platform.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationProblem.serviceDisabled);
    }
    final current = await _platform.checkPermission();
    final permission = current == LocationPermission.denied
        ? await _platform.requestPermission()
        : current;
    final problem = switch (permission) {
      LocationPermission.denied => LocationProblem.denied,
      LocationPermission.deniedForever => LocationProblem.deniedForever,
      LocationPermission.whileInUse ||
      LocationPermission.always ||
      LocationPermission.unableToDetermine => null,
    };
    if (problem != null) throw LocationUnavailable(problem);
  }
}
