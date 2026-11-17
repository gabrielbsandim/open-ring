import 'dart:async';

import 'package:meta/meta.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

enum WorkoutNoticeAction { pause, resume, stop, save, keep, reconnect }

@immutable
final class WorkoutNotice {
  const new({
    required this.title,
    required this.text,
    required this.elapsed,
    required this.running,
    this.confirming = false,
    this.ringLost = false,
    this.publicTitle,
    this.publicText,
    this.labels = const WorkoutNoticeLabels(),
  });

  final String title;
  final String text;
  final Duration elapsed;
  final bool running;

  /// The end question is showing: its actions are save and keep.
  final bool confirming;

  /// The ring went silent: a reconnect action is offered.
  final bool ringLost;

  /// The lock screen version with no heart rate, null when it shows all.
  final String? publicTitle;
  final String? publicText;
  final WorkoutNoticeLabels labels;

  @override
  bool operator ==(Object other) =>
      other is WorkoutNotice &&
      other.title == title &&
      other.text == text &&
      other.elapsed == elapsed &&
      other.running == running &&
      other.confirming == confirming &&
      other.ringLost == ringLost &&
      other.publicTitle == publicTitle &&
      other.publicText == publicText;

  @override
  int get hashCode => Object.hash(
    title,
    text,
    elapsed,
    running,
    confirming,
    ringLost,
    publicTitle,
    publicText,
  );
}

/// The heads up alert sent once when the ring stops sending heart rate.
@immutable
final class WorkoutAlert {
  const new({
    required this.title,
    required this.text,
    this.channel = 'Workout alerts',
    this.reconnect = 'Reconnect',
  });

  final String title;
  final String text;
  final String channel;
  final String reconnect;

  @override
  bool operator ==(Object other) =>
      other is WorkoutAlert &&
      other.title == title &&
      other.text == text &&
      other.channel == channel &&
      other.reconnect == reconnect;

  @override
  int get hashCode => Object.hash(title, text, channel, reconnect);
}

final class WorkoutNoticeLabels {
  const new({
    this.channel = 'Workout',
    this.pause = 'Pause',
    this.resume = 'Resume',
    this.stop = 'End',
    this.paused = 'Paused',
    this.decimalSeparator = '.',
    this.types = const {},
    this.zoneTitle = _zoneTitle,
    this.ringLostTitle = _ringLostTitle,
    this.pausedTitle = _pausedTitle,
    this.pausedAt = _pausedAt,
    this.recording = 'Recording the time',
    this.gpsLost = 'GPS signal lost',
    this.speed = 'km/h',
    this.speedImperial = 'mph',
    this.save = 'Save',
    this.keep = 'Continue',
    this.reconnect = 'Reconnect',
    this.confirmTitle = 'End and save the workout?',
    this.confirmText = _confirmText,
    this.alertChannel = 'Workout alerts',
    this.ringLostAlertTitle = 'The ring stopped sending heart rate',
    this.ringLostAlertText =
        'The workout is still recording. Tap to reconnect.',
  });

  final String channel;
  final String pause;
  final String resume;
  final String stop;
  final String paused;
  final String decimalSeparator;
  final Map<WorkoutType, String> types;
  final String Function(String type, int zone) zoneTitle;
  final String Function(String type) ringLostTitle;
  final String Function(String type) pausedTitle;
  final String Function(String time) pausedAt;
  final String recording;
  final String gpsLost;
  final String speed;
  final String speedImperial;
  final String save;
  final String keep;
  final String reconnect;
  final String confirmTitle;
  final String Function(String time, String? distance) confirmText;
  final String alertChannel;
  final String ringLostAlertTitle;
  final String ringLostAlertText;
}

String _confirmText(String time, String? distance) =>
    [time, ?distance, 'paused'].join(' · ');

String _zoneTitle(String type, int zone) => '$type · Zone $zone';

String _ringLostTitle(String type) => '$type · ring out of range';

String _pausedTitle(String type) => '$type · Paused';

String _pausedAt(String time) => 'Paused at $time';

final class WorkoutNotifierFailure implements Exception {
  const new();
}

abstract interface class WorkoutNotifier {
  Future<void> show(WorkoutNotice notice);

  Future<void> hide();

  Future<void> alert(WorkoutAlert alert);

  Future<void> clearAlert();

  Stream<WorkoutNoticeAction> get actions;
}

final class InMemoryWorkoutNotifier implements WorkoutNotifier {
  final List<WorkoutNotice> shown = [];
  final _actions = StreamController<WorkoutNoticeAction>.broadcast(sync: true);
  final List<WorkoutAlert> alerts = [];
  int hides = 0;
  int alertClears = 0;
  bool failing = false;

  @override
  Stream<WorkoutNoticeAction> get actions => _actions.stream;

  void tap(WorkoutNoticeAction action) => _actions.add(action);

  @override
  Future<void> show(WorkoutNotice notice) async {
    _failWhenAsked();
    shown.add(notice);
  }

  @override
  Future<void> hide() async {
    _failWhenAsked();
    hides++;
  }

  @override
  Future<void> alert(WorkoutAlert alert) async {
    _failWhenAsked();
    alerts.add(alert);
  }

  @override
  Future<void> clearAlert() async {
    _failWhenAsked();
    alertClears++;
  }

  void _failWhenAsked() {
    if (!failing) return;
    throw const WorkoutNotifierFailure();
  }
}
