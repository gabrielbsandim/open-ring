import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';

// HealthKit has no settings deep link, so iOS opens the app's own settings
// page, which lists the Health access.
final class MethodChannelHealthSettingsOpener implements HealthSettingsOpener {
  const new({
    required this.fallback,
    this.channel = const MethodChannel(channelName),
  });

  static const channelName = 'gbs.openring.app/health_settings';

  final Future<void> Function() fallback;
  final MethodChannel channel;

  @override
  Future<void> open() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      await fallback();
      return;
    }
    await channel.invokeMethod<void>('open');
  }
}
