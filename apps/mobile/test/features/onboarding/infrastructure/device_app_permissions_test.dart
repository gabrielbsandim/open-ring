import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/infrastructure/device_app_permissions.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';

import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/workout_fakes.dart';

class _MissingBackgroundPlatform extends FakeAppPermissions {
  @override
  Future<PermissionStatus> status(AppPermission permission) async {
    if (permission == AppPermission.backgroundExecution) {
      throw MissingPluginException('no battery list');
    }
    return await super.status(permission);
  }
}

class _MissingLocation extends FakeLocationAccess {
  @override
  Future<LocationAccessStatus> status() async =>
      throw MissingPluginException('no location plugin');
}

void main() {
  late FakeAppPermissions platform;
  late FakeBatterySettings battery;
  late FakeLocationAccess location;
  late DeviceAppPermissions permissions;

  setUp(() {
    platform = FakeAppPermissions();
    battery = FakeBatterySettings();
    location = FakeLocationAccess();
    permissions = DeviceAppPermissions(
      platform: platform,
      battery: battery,
      location: location,
    );
  });

  test('bluetooth and notifications stay on the platform port', () async {
    platform.statuses[AppPermission.notifications] = PermissionStatus.granted;

    expect(
      await permissions.status(AppPermission.notifications),
      PermissionStatus.granted,
    );
    await permissions.request(AppPermission.bluetooth);
    await permissions.openSettings();

    expect(platform.requests, [AppPermission.bluetooth]);
    expect(platform.settingsOpened, 1);
  });

  test('background status reads the platform exemption', () async {
    platform.statuses[AppPermission.backgroundExecution] =
        PermissionStatus.granted;

    expect(
      await permissions.status(AppPermission.backgroundExecution),
      PermissionStatus.granted,
    );
  });

  test(
    'requesting background opens the battery settings, not a prompt',
    () async {
      expect(
        await permissions.request(AppPermission.backgroundExecution),
        PermissionStatus.denied,
      );
      expect(battery.opened, 1);
      expect(platform.requests, isEmpty);
    },
  );

  test('background does not apply where the platform has no list', () async {
    final missing = DeviceAppPermissions(
      platform: _MissingBackgroundPlatform(),
      battery: battery,
      location: location,
    );

    expect(
      await missing.status(AppPermission.backgroundExecution),
      PermissionStatus.notApplicable,
    );
  });

  test('location does not apply where the plugin is missing', () async {
    final missing = DeviceAppPermissions(
      platform: platform,
      battery: battery,
      location: _MissingLocation(),
    );

    expect(
      await missing.status(AppPermission.location),
      PermissionStatus.notApplicable,
    );
  });

  test('every location status maps to a card state', () {
    expect(
      DeviceAppPermissions.statusOf(LocationAccessStatus.granted),
      PermissionStatus.granted,
    );
    expect(
      DeviceAppPermissions.statusOf(LocationAccessStatus.denied),
      PermissionStatus.denied,
    );
    expect(
      DeviceAppPermissions.statusOf(LocationAccessStatus.serviceDisabled),
      PermissionStatus.denied,
    );
    expect(
      DeviceAppPermissions.statusOf(LocationAccessStatus.deniedForever),
      PermissionStatus.permanentlyDenied,
    );
  });

  test('requesting location asks through the workout port', () async {
    expect(
      await permissions.request(AppPermission.location),
      PermissionStatus.granted,
    );

    expect(location.requests, 1);
    expect(location.locationSettings, 0);
  });

  test('requesting location with the service off opens its settings', () async {
    location
      ..current = LocationAccessStatus.serviceDisabled
      ..afterRequest = LocationAccessStatus.serviceDisabled;

    expect(
      await permissions.request(AppPermission.location),
      PermissionStatus.denied,
    );

    expect(location.locationSettings, 1);
  });
}
