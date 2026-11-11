import 'package:flutter/services.dart';
import 'package:ring_notifications/ring_notifications.dart';

final class MethodChannelSyncService {
  const new([
    this._channel = const MethodChannel(RingNotificationsChannel.name),
  ]);

  final MethodChannel _channel;

  Future<void> start({required String channelName, required String title}) =>
      _channel.invokeMethod<void>(
        RingNotificationsChannel.startSyncServiceMethod,
        {'channelName': channelName, 'title': title},
      );

  Future<void> stop() => _channel.invokeMethod<void>(
    RingNotificationsChannel.stopSyncServiceMethod,
  );
}
