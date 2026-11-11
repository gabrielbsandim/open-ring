import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

const _watch = 'com.garmin.android.apps.connectmobile';

final class _Own implements WorkoutHistoryReader {
  List<WorkoutListItem> items = [];

  @override
  Future<List<WorkoutListItem>> recent({required int limit}) async =>
      items.take(limit).toList();

  @override
  Future<SavedWorkout?> byId(int id) async => null;
}

final class _Imported implements ImportedWorkoutReader {
  List<String> priority = const [ringSource, _watch];
  List<ImportedWorkout> items = [];

  @override
  Future<ImportedWorkouts> recent({required int limit}) async =>
      (priority: priority, workouts: items.take(limit).toList());

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) async => null;
}

WorkoutListItem _own(int id, DateTime start, {int minutes = 30}) =>
    WorkoutListItem(
      id: id,
      type: WorkoutType.running,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      utcOffset: Duration.zero,
      elapsed: Duration(minutes: minutes),
      distanceMeters: 5000,
      averageHeartRate: 150,
    );

ImportedWorkout _imported(String id, DateTime start, {int minutes = 30}) =>
    ImportedWorkout(
      recordId: id,
      source: _watch,
      type: WorkoutType.cycling,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      utcOffset: Duration.zero,
    );

void main() {
  final morning = DateTime.utc(2026, 11, 10, 7);
  final evening = DateTime.utc(2026, 11, 10, 18);

  late _Own own;
  late _Imported imported;
  late ProviderContainer container;

  setUp(() {
    own = _Own();
    imported = _Imported();
    container = ProviderContainer.test(
      overrides: [
        workoutHistoryReaderProvider.overrideWithValue(own),
        importedWorkoutReaderProvider.overrideWithValue(imported),
      ],
    );
  });

  Future<WorkoutEntry?> last() => container.read(lastWorkoutProvider.future);

  test('nothing recorded anywhere gives no last workout', () async {
    expect(await last(), isNull);
  });

  test('a newer workout from another app is the last one', () async {
    own.items = [_own(1, morning)];
    imported.items = [_imported('w1', evening)];

    expect(await last(), isA<ImportedWorkout>());
    expect((await last())!.start, evening);
  });

  test('a newer OpenRing workout is the last one', () async {
    own.items = [_own(1, evening)];
    imported.items = [_imported('w1', morning)];

    expect(await last(), isA<WorkoutListItem>());
  });

  test(
    'OpenRing wins an overlap even when the other one starts later',
    () async {
      own.items = [_own(1, evening, minutes: 60)];
      imported.items = [
        _imported('w1', evening.add(const Duration(minutes: 10))),
      ];

      final entry = await last();

      expect(entry, isA<WorkoutListItem>());
      expect((entry! as WorkoutListItem).id, 1);
    },
  );

  test(
    'the priority order decides an overlap the same way as the history',
    () async {
      own.items = [_own(1, evening, minutes: 60)];
      imported
        ..priority = const [_watch, ringSource]
        ..items = [_imported('w1', evening.add(const Duration(minutes: 10)))];

      expect(await last(), isA<ImportedWorkout>());
      expect(
        (await container.read(recentWorkoutsProvider.future)).first,
        await last(),
      );
    },
  );

  test('a new import shows after the data revision moves', () async {
    own.items = [_own(1, morning)];
    expect(await last(), isA<WorkoutListItem>());

    imported.items = [_imported('w1', evening)];
    container.read(dataRevisionProvider.notifier).bump();

    expect(await last(), isA<ImportedWorkout>());
  });
}
