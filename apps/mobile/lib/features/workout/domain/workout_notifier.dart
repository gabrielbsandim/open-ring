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
  final WorkoutNoticeLabels labels;

  @override
  bool operator ==(Object other) =>
      other is WorkoutNotice &&
      other.title == title &&
      other.text == text &&
      other.elapsed == elapsed &&
      other.running == running &&
      other.confirming == confirming &&
      other.ringLost == ringLost;

  @override
  int get hashCode =>
      Object.hash(title, text, elapsed, running, confirming, ringLost);
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

  Stream<WorkoutNoticeAction> get actions;
}

final class InMemoryWorkoutNotifier implements WorkoutNotifier {
  final List<WorkoutNotice> shown = [];
  final _actions = StreamController<WorkoutNoticeAction>.broadcast(sync: true);
  int hides = 0;
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

  void _failWhenAsked() {
    if (!failing) return;
    throw const WorkoutNotifierFailure();
  }
}
