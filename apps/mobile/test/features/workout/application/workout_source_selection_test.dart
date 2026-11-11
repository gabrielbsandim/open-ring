import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/workout/application/workout_source_selection.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

const _watch = 'com.garmin.android.apps.connectmobile';
const _fit = 'com.google.android.apps.fitness';

final _run = DateTime.utc(2026, 11, 9, 18);

WorkoutListItem _own(int id, DateTime start, {int minutes = 40}) =>
    WorkoutListItem(
      id: id,
      type: WorkoutType.running,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      utcOffset: Duration.zero,
      elapsed: Duration(minutes: minutes),
    );

ImportedWorkout _imported(
  String id,
  String source,
  DateTime start, {
  int minutes = 40,
}) => ImportedWorkout(
  recordId: id,
  source: source,
  type: WorkoutType.running,
  start: start,
  end: start.add(Duration(minutes: minutes)),
  utcOffset: Duration.zero,
);

List<String> _ids(List<WorkoutEntry> entries) => [
  for (final entry in entries)
    switch (entry) {
      WorkoutListItem(:final id) => '$id',
      ImportedWorkout(:final recordId) => recordId,
    },
];

void main() {
  test('the higher source wins an overlap and nothing is merged', () {
    final entries = [
      _own(1, _run),
      _imported('w1', _watch, _run.add(const Duration(minutes: 5))),
    ];

    expect(_ids(selectWorkouts(entries, const [ringSource, _watch])), ['1']);
    expect(_ids(selectWorkouts(entries, const [_watch, ringSource])), ['w1']);
  });

  test('workouts that do not overlap are all kept, newest first', () {
    final entries = [
      _own(1, _run.subtract(const Duration(days: 1))),
      _imported('w1', _watch, _run),
      _imported('w2', _fit, _run.add(const Duration(hours: 2))),
    ];

    expect(_ids(selectWorkouts(entries, const [ringSource, _watch, _fit])), [
      'w2',
      'w1',
      '1',
    ]);
  });

  test('two overlapping workouts of one source both stay', () {
    final entries = [
      _imported('w1', _watch, _run),
      _imported('w2', _watch, _run.add(const Duration(minutes: 10))),
    ];

    expect(_ids(selectWorkouts(entries, const [ringSource, _watch])), [
      'w2',
      'w1',
    ]);
  });

  test('a dropped workout does not hide a third one', () {
    final entries = [
      _own(1, _run, minutes: 30),
      _imported('w1', _watch, _run.add(const Duration(minutes: 20))),
      _imported('w2', _fit, _run.add(const Duration(minutes: 45))),
    ];

    expect(_ids(selectWorkouts(entries, const [ringSource, _watch, _fit])), [
      'w2',
      '1',
    ]);
  });

  test('touching end and start is not an overlap', () {
    final entries = [
      _own(1, _run),
      _imported('w1', _watch, _run.add(const Duration(minutes: 40))),
    ];

    expect(selectWorkouts(entries, const [ringSource, _watch]), hasLength(2));
  });
}
