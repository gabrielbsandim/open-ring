import 'package:geolocator/geolocator.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';

final class GeolocatorLocationAccess implements LocationAccess {
  new({GeolocatorPlatform? platform})
    : _platform = platform ?? GeolocatorPlatform.instance;

  final GeolocatorPlatform _platform;

  @override
  Future<LocationAccessStatus> status() => _resolve(ask: false);

  @override
  Future<LocationAccessStatus> request() => _resolve(ask: true);

  @override
  Future<void> openAppSettings() => _platform.openAppSettings();

  @override
  Future<void> openLocationSettings() => _platform.openLocationSettings();

  static LocationAccessStatus statusOf(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.denied => LocationAccessStatus.denied,
        LocationPermission.deniedForever => LocationAccessStatus.deniedForever,
        LocationPermission.whileInUse ||
        LocationPermission.always ||
        LocationPermission.unableToDetermine => LocationAccessStatus.granted,
      };

  Future<LocationAccessStatus> _resolve({required bool ask}) async {
    if (!await _platform.isLocationServiceEnabled()) {
      return LocationAccessStatus.serviceDisabled;
    }
    final current = await _platform.checkPermission();
    if (!ask || current != LocationPermission.denied) return statusOf(current);
    return statusOf(await _platform.requestPermission());
  }
}
