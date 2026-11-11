import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/infrastructure/geolocator_location_source.dart';

final stamp = DateTime.utc(2026, 11, 10, 7);

const notice = LocationNotice(
  title: 'Treino OpenRing',
  text: 'Gravando sua rota',
  channel: 'Treino',
);

Position position({bool hasAccuracy = true, bool hasAltitude = true}) =>
    Position(
      latitude: -23.55,
      longitude: -46.63,
      timestamp: stamp,
      accuracy: 4,
      altitude: 760,
      altitudeAccuracy: 3,
      heading: 0,
      headingAccuracy: 0,
      speed: 3,
      speedAccuracy: 1,
      hasAccuracy: hasAccuracy,
      hasAltitude: hasAltitude,
    );

class FakeGeolocator extends Fake implements GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission granted = LocationPermission.whileInUse;
  List<Position> positions = [];
  int requests = 0;
  LocationSettings? settings;

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
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings = locationSettings;
    return Stream.fromIterable(positions);
  }
}

void main() {
  test('maps positions to fixes, unknown accuracy to infinity', () async {
    final platform = FakeGeolocator()
      ..positions = [
        position(),
        position(hasAccuracy: false, hasAltitude: false),
      ];
    final source = GeolocatorLocationSource(platform: platform);

    final fixes = await source.fixes(notice).toList();

    expect(fixes.first.at, stamp);
    expect(fixes.first.latitude, -23.55);
    expect(fixes.first.accuracyMeters, 4);
    expect(fixes.first.altitudeMeters, 760);
    expect(fixes.last.accuracyMeters, double.infinity);
    expect(fixes.last.altitudeMeters, isNull);
  });

  test('asks for permission once when it was never granted', () async {
    final platform = FakeGeolocator()..permission = LocationPermission.denied;

    await GeolocatorLocationSource(platform: platform).fixes(notice).toList();

    expect(platform.requests, 1);
    expect(platform.settings, isNotNull);
  });

  Future<LocationProblem?> problemOf(FakeGeolocator platform) async {
    try {
      await GeolocatorLocationSource(platform: platform).fixes(notice).toList();
      return null;
    } on LocationUnavailable catch (error) {
      return error.problem;
    }
  }

  test(
    'reports a disabled service, a refusal and a permanent refusal',
    () async {
      expect(
        await problemOf(FakeGeolocator()..serviceEnabled = false),
        LocationProblem.serviceDisabled,
      );
      expect(
        await problemOf(
          FakeGeolocator()
            ..permission = LocationPermission.denied
            ..granted = LocationPermission.denied,
        ),
        LocationProblem.denied,
      );
      final forever = FakeGeolocator()
        ..permission = LocationPermission.deniedForever;
      expect(await problemOf(forever), LocationProblem.deniedForever);
      expect(forever.requests, 0);
      expect(forever.settings, isNull);
    },
  );

  test('Android runs a foreground service with a notification', () {
    final settings = GeolocatorLocationSource(
      platform: FakeGeolocator(),
      platformType: TargetPlatform.android,
    ).settings(notice);

    expect(settings, isA<AndroidSettings>());
    final android = settings as AndroidSettings;
    expect(android.accuracy, LocationAccuracy.best);
    expect(android.intervalDuration, const Duration(seconds: 1));
    final notification = android.foregroundNotificationConfig!;
    expect(notification.notificationTitle, notice.title);
    expect(notification.notificationText, notice.text);
    expect(notification.notificationChannelName, notice.channel);
    expect(notification.setOngoing, isTrue);
  });

  test('iOS keeps updating in the background with the indicator', () {
    final settings = GeolocatorLocationSource(
      platform: FakeGeolocator(),
      platformType: TargetPlatform.iOS,
    ).settings(notice);

    expect(settings, isA<AppleSettings>());
    final apple = settings as AppleSettings;
    expect(apple.allowBackgroundLocationUpdates, isTrue);
    expect(apple.showBackgroundLocationIndicator, isTrue);
    expect(apple.pauseLocationUpdatesAutomatically, isFalse);
    expect(apple.activityType, ActivityType.fitness);
  });
}
