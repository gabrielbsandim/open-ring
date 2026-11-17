import 'dart:async';

import 'package:flutter/services.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:ring_notifications/ring_notifications.dart';

final class MethodChannelWorkoutNotifier implements WorkoutNotifier {
  new([this._channel = const MethodChannel(RingNotificationsChannel.name)]);

  static const workoutLink = 'openring://widget/activity/live-workout';

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
        'link': workoutLink,
      });

  @override
  Future<void> hide() =>
      _channel.invokeMethod<void>(RingNotificationsChannel.hideWorkoutMethod);

  Future<void> _onCall(MethodCall call) async {
    if (call.method != RingNotificationsChannel.workoutActionMethod) return;
    final action = WorkoutNoticeAction.values.asNameMap()[call.arguments];
    if (action == null) return;
    _actions.add(action);
  }
}
