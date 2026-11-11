import 'package:flutter/services.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';

final class MethodChannelAppPermissions implements AppPermissions {
  const new([this._channel = const MethodChannel(channelName)]);

  static const channelName = 'gbs.openring.app/permissions';

  final MethodChannel _channel;

  @override
  Future<PermissionStatus> status(AppPermission permission) =>
      _call('status', permission);

  @override
  Future<PermissionStatus> request(AppPermission permission) =>
      _call('request', permission);

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  Future<PermissionStatus> _call(
    String method,
    AppPermission permission,
  ) async {
    final result = await _channel.invokeMethod<String>(method, permission.name);
    return PermissionStatus.values.asNameMap()[result] ??
        PermissionStatus.denied;
  }
}
