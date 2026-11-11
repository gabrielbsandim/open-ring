import 'package:flutter/services.dart';
import 'package:open_ring/features/onboarding/infrastructure/method_channel_app_permissions.dart';
import 'package:open_ring/features/ring/domain/battery_settings.dart';

final class MethodChannelBatterySettings implements BatterySettings {
  const new([
    this._channel = const MethodChannel(
      MethodChannelAppPermissions.channelName,
    ),
  ]);

  static const openMethod = 'openBatterySettings';

  final MethodChannel _channel;

  @override
  Future<void> open() async {
    try {
      await _channel.invokeMethod<void>(openMethod);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
