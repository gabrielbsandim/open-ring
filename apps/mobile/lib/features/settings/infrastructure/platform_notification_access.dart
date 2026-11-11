import 'package:flutter/services.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/infrastructure/method_channel_app_permissions.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';

final class PlatformNotificationAccess implements NotificationAccess {
  const new(
    this._permissions, [
    this._channel = const MethodChannel(
      MethodChannelAppPermissions.channelName,
    ),
  ]);

  static const openMethod = 'openNotificationSettings';

  final AppPermissions _permissions;
  final MethodChannel _channel;

  @override
  Future<bool> enabled() async =>
      (await _permissions.status(AppPermission.notifications)).isGranted;

  // Only the Android channel opens the notification page; elsewhere the app's
  // settings page holds the switch.
  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>(openMethod);
    } on MissingPluginException {
      await _permissions.openSettings();
    }
  }
}
