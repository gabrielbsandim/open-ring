import 'dart:async';

import 'package:meta/meta.dart';

enum WorkoutNoticeAction { pause, resume, stop }

@immutable
final class WorkoutNotice {
  const new({
    required this.title,
    required this.text,
    required this.elapsed,
    required this.running,
    this.labels = const WorkoutNoticeLabels(),
  });

  final String title;
  final String text;
  final Duration elapsed;
  final bool running;
  final WorkoutNoticeLabels labels;

  @override
  bool operator ==(Object other) =>
      other is WorkoutNotice &&
      other.title == title &&
      other.text == text &&
      other.elapsed == elapsed &&
      other.running == running;

  @override
  int get hashCode => Object.hash(title, text, elapsed, running);
}

final class WorkoutNoticeLabels {
  const new({
    this.channel = 'Workout',
    this.pause = 'Pause',
    this.resume = 'Resume',
    this.stop = 'End',
    this.paused = 'Paused',
    this.decimalSeparator = '.',
  });

  final String channel;
  final String pause;
  final String resume;
  final String stop;
  final String paused;
  final String decimalSeparator;
}

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
