import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/application/export_providers.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/domain/file_sharer.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/location_access_provider.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/domain/location_fix.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';

final workoutStart = DateTime.utc(2026, 11, 10, 7);

const double metersPerDegreeLatitude = earthMeanRadiusMeters * math.pi / 180;

const testNotice = LocationNotice(
  title: 'Workout title',
  text: 'Workout text',
  channel: 'Workout channel',
);

class FakeClock {
  new(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

LocationFix fixAt(
  Duration offset, {
  required double northMeters,
  double accuracyMeters = 5,
  double startLatitude = -23.55,
  double longitude = -46.63,
}) => LocationFix(
  at: workoutStart.add(offset),
  latitude: startLatitude + northMeters / metersPerDegreeLatitude,
  longitude: longitude,
  accuracyMeters: accuracyMeters,
);

class FakeHeartRateSource implements LiveHeartRateSource {
  StreamController<int>? _controller;
  int listens = 0;
  int cancels = 0;
  int pauses = 0;
  int resumes = 0;

  bool get listening => _controller?.hasListener ?? false;

  bool get paused => _controller?.isPaused ?? false;

  @override
  Stream<int> bpm() {
    final controller = StreamController<int>(
      sync: true,
      onListen: () => listens++,
      onPause: () => pauses++,
      onResume: () => resumes++,
      onCancel: () => cancels++,
    );
    _controller = controller;
    return controller.stream;
  }

  void emit(int bpm) {
    if (paused) return;
    _controller?.add(bpm);
  }

  void fail(Object error) => _controller?.addError(error);

  void close() => unawaited(_controller?.close());
}

class FakeLocationSource implements LocationSource {
  StreamController<LocationFix>? _controller;
  int listens = 0;
  int cancels = 0;
  LocationNotice? notice;

  bool get listening => _controller?.hasListener ?? false;

  @override
  Stream<LocationFix> fixes(LocationNotice notice) {
    this.notice = notice;
    final controller = StreamController<LocationFix>(
      sync: true,
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
    _controller = controller;
    return controller.stream;
  }

  void emit(LocationFix fix) => _controller?.add(fix);

  void fail(Object error) => _controller?.addError(error);

  void close() => unawaited(_controller?.close());
}

class FlakyWorkoutStore implements WorkoutStore {
  new(this._inner, {this.failures = 1});

  final WorkoutStore _inner;
  int failures;

  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) {
    if (failures <= 0) return _inner.save(workout, at: at);
    failures--;
    return Future.error(StateError('disk full'));
  }

  @override
  Future<bool> delete(int id) => _inner.delete(id);
}

class FakeLocationAccess implements LocationAccess {
  new({
    this.current = LocationAccessStatus.denied,
    this.afterRequest = LocationAccessStatus.granted,
  });

  LocationAccessStatus current;
  LocationAccessStatus afterRequest;
  bool fail = false;
  int requests = 0;
  int appSettings = 0;
  int locationSettings = 0;

  @override
  Future<LocationAccessStatus> status() async {
    if (fail) throw StateError('location service unreachable');
    return current;
  }

  @override
  Future<LocationAccessStatus> request() async {
    requests++;
    if (fail) throw StateError('location service unreachable');
    return current = afterRequest;
  }

  @override
  Future<void> openAppSettings() async => appSettings++;

  @override
  Future<void> openLocationSettings() async => locationSettings++;
}

class RecordingWorkoutStore implements WorkoutStore {
  final saved = <FinishedWorkout>[];
  final deleted = <int>[];

  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) async {
    saved.add(workout);
    return saved.length;
  }

  @override
  Future<bool> delete(int id) async {
    if (id < 1 || id > saved.length || deleted.contains(id)) return false;
    deleted.add(id);
    return true;
  }
}

class MemoryWorkoutHistory implements WorkoutStore, WorkoutHistoryReader {
  new({Iterable<SavedWorkout> seed = const []}) {
    for (final saved in seed) {
      _saved[saved.id] = saved;
      _next = _next > saved.id ? _next : saved.id + 1;
    }
  }

  final _saved = <int, SavedWorkout>{};
  var _next = 1;
  bool failDelete = false;

  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) async {
    final id = _next++;
    _saved[id] = SavedWorkout(
      id: id,
      workout: workout,
      utcOffset: workout.start.timeZoneOffset,
      health: WorkoutHealthStatus.pending,
    );
    return id;
  }

  @override
  Future<bool> delete(int id) async {
    if (failDelete) throw StateError('disk full');
    return _saved.remove(id) != null;
  }

  @override
  Future<SavedWorkout?> byId(int id) async => _saved[id];

  @override
  Future<List<WorkoutListItem>> recent({required int limit}) async {
    final newest = _saved.values.toList()
      ..sort((a, b) => b.workout.start.compareTo(a.workout.start));
    return [
      for (final saved in newest.take(limit))
        WorkoutListItem(
          id: saved.id,
          type: saved.workout.type,
          start: saved.workout.start,
          end: saved.workout.end,
          utcOffset: saved.utcOffset,
          elapsed: saved.workout.elapsed,
          distanceMeters: saved.workout.distanceMeters,
          averageHeartRate: saved.workout.averageHeartRate,
          activeKilocalories: saved.workout.activeKilocalories,
          health: saved.health,
        ),
    ];
  }
}

final class FakeRouteExporter implements DataExporter {
  final routes = <WorkoutRoute>[];
  final csvExports = <(FinishedWorkout, Duration)>[];
  bool fail = false;

  @override
  Future<ExportResult> export(ExportRequest request) =>
      throw UnimplementedError();

  @override
  Future<ExportFile> exportRoute(WorkoutRoute route) async {
    if (fail) throw StateError('disk full');
    routes.add(route);
    return const ExportFile(
      path: '/tmp/openring-export-1/openring-route-20261110-073000.gpx',
      mimeType: ExportFile.gpxMimeType,
    );
  }

  @override
  Future<ExportFile> exportWorkoutCsv(
    FinishedWorkout workout, {
    required Duration offset,
  }) async {
    if (fail) throw StateError('disk full');
    csvExports.add((workout, offset));
    return const ExportFile(
      path: '/tmp/openring-export-1/openring-workout-20261110-073000.csv',
      mimeType: ExportFile.csvMimeType,
    );
  }
}

final class RecordingFileSharer implements FileSharer {
  final shared = <(List<ExportFile>, String)>[];
  bool fail = false;

  @override
  Future<void> share(List<ExportFile> files, {required String subject}) async {
    if (fail) throw const FileShareException('no share sheet');
    shared.add((files, subject));
  }
}

class WorkoutRig {
  new({
    WorkoutStore? store,
    this.profile = const UserProfile(birthYear: 1990, weightKilograms: 70),
    LocationAccessStatus access = LocationAccessStatus.granted,
    this.units = UnitSystem.metric,
  }) : store = store ?? RecordingWorkoutStore(),
       access = FakeLocationAccess(current: access);

  final WorkoutStore store;
  final exporter = FakeRouteExporter();
  final sharer = RecordingFileSharer();
  final UserProfile? profile;
  final UnitSystem units;
  final FakeLocationAccess access;
  final clock = FakeClock(workoutStart);
  final ticks = StreamController<void>.broadcast(sync: true);
  final heartRate = FakeHeartRateSource();
  final location = FakeLocationSource();
  var _north = 0.0;
  var _east = 0.0;
  var _walked = 0.0;

  List<Override> overrides() => [
    clockProvider.overrideWithValue(clock.call),
    workoutTicksProvider.overrideWithValue(() => ticks.stream),
    liveHeartRateSourceProvider.overrideWithValue(heartRate),
    locationSourceProvider.overrideWithValue(location),
    workoutStoreProvider.overrideWithValue(store),
    userProfileStoreProvider.overrideWithValue(
      InMemoryUserProfileStore(profile),
    ),
    locationAccessProvider.overrideWithValue(access),
    workoutHistoryReaderProvider.overrideWithValue(history),
    dataExporterProvider.overrideWithValue(exporter),
    fileSharerProvider.overrideWithValue(sharer),
    unitSystemStoreProvider.overrideWithValue(InMemoryUnitSystemStore(units)),
  ];

  WorkoutHistoryReader get history => switch (store) {
    final WorkoutHistoryReader reader => reader,
    _ => const EmptyWorkoutHistoryReader(),
  };

  void second({int? bpm, double? meters, double accuracyMeters = 5}) {
    clock.advance(const Duration(seconds: 1));
    if (meters != null) {
      final leg = _walked ~/ 200 % 4;
      _walked += meters;
      switch (leg) {
        case 0:
          _north += meters;
        case 1:
          _east += meters;
        case 2:
          _north -= meters;
        default:
          _east -= meters;
      }
      location.emit(
        LocationFix(
          at: clock.now,
          latitude: -23.55 + _north / metersPerDegreeLatitude,
          longitude: -46.63 + _east / metersPerDegreeLatitude,
          accuracyMeters: accuracyMeters,
        ),
      );
    }
    if (bpm != null) heartRate.emit(bpm);
    ticks.add(null);
  }

  void run(int seconds, {int? bpm = 148, double? meters = 3}) {
    for (var i = 0; i < seconds; i++) {
      second(bpm: bpm == null ? null : bpm + i % 7, meters: meters);
    }
  }
}
