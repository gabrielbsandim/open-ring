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

/// The dismissible notice left once a workout ends, saved or not.
@immutable
final class WorkoutEndNotice {
  const new({
    required this.title,
    required this.text,
    required this.action,
    required this.link,
    this.channel = 'Workout',
    this.publicText,
    this.failed = false,
  });

  final String title;
  final String text;
  final String action;
  final String link;
  final String channel;

  /// The lock screen text with no heart rate, null when it shows all.
  final String? publicText;

  /// The save failed, so the workout lives only in this process.
  final bool failed;

  @override
  bool operator ==(Object other) =>
      other is WorkoutEndNotice &&
      other.title == title &&
      other.text == text &&
      other.action == action &&
      other.link == link &&
      other.channel == channel &&
      other.publicText == publicText &&
      other.failed == failed;

  @override
  int get hashCode =>
      Object.hash(title, text, action, link, channel, publicText, failed);
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
    this.savedTitle = 'Workout saved',
    this.savedHeartRate = _savedHeartRate,
    this.failedTitle = 'The workout was not saved',
    this.failedText =
        'Open the app to try again. If you close it, the workout is saved up '
        'to its last minute the next time the app opens.',
    this.viewSummary = 'See workout summary',
    this.open = 'Open',
    this.recoveredTitle = _recoveredTitle,
    this.recoveredText = _recoveredText,
    this.clockOrDay = _clockOrDay,
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
  final String savedTitle;
  final String Function(int bpm) savedHeartRate;
  final String failedTitle;
  final String failedText;
  final String viewSummary;
  final String open;
  final String Function(String time) recoveredTitle;
  final String Function(String elapsed, String? distance) recoveredText;

  /// The wall time at the given offset; the localized one adds the day when it is
  /// not the day of now.
  final String Function(DateTime instant, Duration offset, DateTime now)
  clockOrDay;
}

String _recoveredTitle(String time) => 'Workout saved until $time';

String _recoveredText(String elapsed, String? distance) =>
    'OpenRing stopped during the workout. '
    '${[elapsed, ?distance].join(', ')} kept.';

String _clockOrDay(DateTime instant, Duration offset, DateTime now) {
  final wall = instant.toUtc().add(offset);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(wall.hour)}:${two(wall.minute)}';
}

String _savedHeartRate(int bpm) => 'Avg HR $bpm';

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

  Future<void> ended(WorkoutEndNotice notice);

  Future<void> clearEnded();

  Stream<WorkoutNoticeAction> get actions;
}

final class InMemoryWorkoutNotifier implements WorkoutNotifier {
  final List<WorkoutNotice> shown = [];
  final _actions = StreamController<WorkoutNoticeAction>.broadcast(sync: true);
  final List<WorkoutAlert> alerts = [];
  int hides = 0;
  int alertClears = 0;
  final List<WorkoutEndNotice> endedNotices = [];
  int endedClears = 0;
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

  @override
  Future<void> ended(WorkoutEndNotice notice) async {
    _failWhenAsked();
    endedNotices.add(notice);
  }

  @override
  Future<void> clearEnded() async {
    _failWhenAsked();
    endedClears++;
  }

  void _failWhenAsked() {
    if (!failing) return;
    throw const WorkoutNotifierFailure();
  }
}
