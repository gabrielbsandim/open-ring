import 'package:flutter/services.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/ring/domain/battery_settings.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';

final class DeviceAppPermissions implements AppPermissions {
  const new({
    required this._platform,
    required this._battery,
    required this._location,
  });

  final AppPermissions _platform;
  final BatterySettings _battery;
  final LocationAccess _location;

  @override
  Future<PermissionStatus> status(AppPermission permission) =>
      switch (permission) {
        AppPermission.bluetooth ||
        AppPermission.notifications => _platform.status(permission),
        AppPermission.backgroundExecution => _backgroundStatus(),
        AppPermission.location => _locationStatus(_location.status),
      };

  @override
  Future<PermissionStatus> request(AppPermission permission) =>
      switch (permission) {
        AppPermission.bluetooth ||
        AppPermission.notifications => _platform.request(permission),
        AppPermission.backgroundExecution => _openBatterySettings(),
        AppPermission.location => _locationStatus(_requestLocation),
      };

  @override
  Future<void> openSettings() => _platform.openSettings();

  // The exemption is only reachable through the system list, so the screen
  // reads the outcome when the app resumes.
  Future<PermissionStatus> _openBatterySettings() async {
    await _battery.open();
    return await _backgroundStatus();
  }

  Future<PermissionStatus> _backgroundStatus() async {
    try {
      return await _platform.status(AppPermission.backgroundExecution);
    } on MissingPluginException {
      return PermissionStatus.notApplicable;
    }
  }

  Future<LocationAccessStatus> _requestLocation() async {
    final result = await _location.request();
    if (result == LocationAccessStatus.serviceDisabled) {
      await _location.openLocationSettings();
    }
    return result;
  }

  static Future<PermissionStatus> _locationStatus(
    Future<LocationAccessStatus> Function() query,
  ) async {
    try {
      return statusOf(await query());
    } on MissingPluginException {
      return PermissionStatus.notApplicable;
    }
  }

  static PermissionStatus statusOf(LocationAccessStatus status) =>
      switch (status) {
        LocationAccessStatus.granted => PermissionStatus.granted,
        LocationAccessStatus.denied ||
        LocationAccessStatus.serviceDisabled => PermissionStatus.denied,
        LocationAccessStatus.deniedForever =>
          PermissionStatus.permanentlyDenied,
      };
}
