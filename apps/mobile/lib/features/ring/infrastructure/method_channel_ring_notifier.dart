import 'package:flutter/services.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:ring_notifications/ring_notifications.dart';

final class MethodChannelRingNotifier implements RingNotifier {
  const new([
    this._channel = const MethodChannel(RingNotificationsChannel.name),
  ]);

  static const ringLink = 'openring://widget/ring';

  final MethodChannel _channel;

  @override
  Future<bool> enabled() async =>
      await _channel.invokeMethod<bool>(
        RingNotificationsChannel.enabledMethod,
      ) ??
      false;

  @override
  Future<void> show(RingNotification notification) =>
      _channel.invokeMethod<void>(RingNotificationsChannel.showMethod, {
        'id': notification.id,
        'channelName': notification.channelName,
        'title': notification.title,
        'body': notification.body,
        'link': ringLink,
      });
}
