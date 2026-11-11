import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/infrastructure/geolocator_location_access.dart';

class _Geolocator extends Fake implements GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission granted = LocationPermission.whileInUse;
  int requests = 0;
  int appSettings = 0;
  int locationSettings = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return true;
  }
}

void main() {
  test('status never prompts', () async {
    final platform = _Geolocator();
    final access = GeolocatorLocationAccess(platform: platform);

    expect(await access.status(), LocationAccessStatus.denied);
    expect(platform.requests, 0);
  });

  test('request prompts only while the permission is undecided', () async {
    final platform = _Geolocator();
    final access = GeolocatorLocationAccess(platform: platform);

    expect(await access.request(), LocationAccessStatus.granted);
    expect(platform.requests, 1);

    platform.permission = LocationPermission.deniedForever;
    expect(await access.request(), LocationAccessStatus.deniedForever);
    expect(platform.requests, 1);
  });

  test('a disabled location service wins over the permission', () async {
    final platform = _Geolocator()
      ..serviceEnabled = false
      ..permission = LocationPermission.always;
    final access = GeolocatorLocationAccess(platform: platform);

    expect(await access.status(), LocationAccessStatus.serviceDisabled);
    expect(await access.request(), LocationAccessStatus.serviceDisabled);
    expect(platform.requests, 0);
  });

  test('maps every permission', () {
    expect(
      {
        for (final permission in LocationPermission.values)
          permission: GeolocatorLocationAccess.statusOf(permission),
      },
      {
        LocationPermission.denied: LocationAccessStatus.denied,
        LocationPermission.deniedForever: LocationAccessStatus.deniedForever,
        LocationPermission.whileInUse: LocationAccessStatus.granted,
        LocationPermission.always: LocationAccessStatus.granted,
        LocationPermission.unableToDetermine: LocationAccessStatus.granted,
      },
    );
  });

  test('opens the right settings page', () async {
    final platform = _Geolocator();
    final access = GeolocatorLocationAccess(platform: platform);

    await access.openAppSettings();
    await access.openLocationSettings();

    expect(platform.appSettings, 1);
    expect(platform.locationSettings, 1);
  });
}
