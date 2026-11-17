import 'dart:async';

import 'package:flutter/services.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:ring_notifications/ring_notifications.dart';

final class MethodChannelWorkoutNotifier implements WorkoutNotifier {
  new([this._channel = const MethodChannel(RingNotificationsChannel.name)]);

  static const workoutLink = 'openring://widget/activity/live-workout';
  static const endedTimeout = Duration(hours: 1);

  final MethodChannel _channel;
  late final _actions = StreamController<WorkoutNoticeAction>.broadcast(
    onListen: () => _channel.setMethodCallHandler(_onCall),
  );

  @override
  Stream<WorkoutNoticeAction> get actions => _actions.stream;

  @override
  Future<void> show(WorkoutNotice notice) =>
      _channel.invokeMethod<void>(RingNotificationsChannel.showWorkoutMethod, {
        'channelName': notice.labels.channel,
        'title': notice.title,
        'text': notice.text,
        'elapsedMs': notice.elapsed.inMilliseconds,
        'running': notice.running,
        'pauseLabel': notice.labels.pause,
        'resumeLabel': notice.labels.resume,
        'stopLabel': notice.labels.stop,
        'confirming': notice.confirming,
        'ringLost': notice.ringLost,
        'saveLabel': notice.labels.save,
        'keepLabel': notice.labels.keep,
        'reconnectLabel': notice.labels.reconnect,
        'publicTitle': notice.publicTitle,
        'publicText': notice.publicText,
        'link': workoutLink,
      });

  @override
  Future<void> hide() =>
      _channel.invokeMethod<void>(RingNotificationsChannel.hideWorkoutMethod);

  @override
  Future<void> alert(WorkoutAlert alert) =>
      _channel.invokeMethod<void>(RingNotificationsChannel.alertWorkoutMethod, {
        'channelName': alert.channel,
        'title': alert.title,
        'text': alert.text,
        'reconnectLabel': alert.reconnect,
      });

  @override
  Future<void> clearAlert() => _channel.invokeMethod<void>(
    RingNotificationsChannel.clearWorkoutAlertMethod,
  );

  @override
  Future<void> ended(WorkoutEndNotice notice) => _channel.invokeMethod<void>(
    RingNotificationsChannel.showWorkoutEndedMethod,
    {
      'channelName': notice.channel,
      'title': notice.title,
      'text': notice.text,
      'actionLabel': notice.action,
      'link': notice.link,
      'timeoutMs': endedTimeout.inMilliseconds,
    },
  );

  @override
  Future<void> clearEnded() => _channel.invokeMethod<void>(
    RingNotificationsChannel.clearWorkoutEndedMethod,
  );

  Future<void> _onCall(MethodCall call) async {
    if (call.method != RingNotificationsChannel.workoutActionMethod) return;
    final action = WorkoutNoticeAction.values.asNameMap()[call.arguments];
    if (action == null) return;
    _actions.add(action);
  }
}
