import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/imported_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/live_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/location_permission_screen.dart';
import 'package:open_ring/features/workout/presentation/recent_workouts_card.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_summary_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../features/workout/presentation/workout_scenarios.dart';
import '../helpers/layout_harness.dart';
import '../helpers/metrics_fakes.dart';
import '../helpers/protocol_lab_fakes.dart';
import '../helpers/ring_fakes.dart';
import '../helpers/settings_fakes.dart';
import '../helpers/workout_fakes.dart';

const _readFailure = FileSystemException('database is locked');
const _importedId = 'garmin-ride';
const _watch = 'com.garmin.android.apps.connectmobile';

final class _FailingHistory implements WorkoutStore, WorkoutHistoryReader {
  @override
  Future<List<WorkoutListItem>> recent({required int limit}) async =>
      throw _readFailure;

  @override
  Future<SavedWorkout?> byId(int id) async => throw _readFailure;

  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) async =>
      throw _readFailure;

  @override
  Future<bool> delete(int id) async => throw _readFailure;
}

final class _Imported implements ImportedWorkoutReader {
  const new({this.workouts = const [], this.fail = false});

  final List<ImportedWorkout> workouts;
  final bool fail;

  @override
  Future<ImportedWorkouts> recent({required int limit}) async {
    if (fail) throw _readFailure;
    return (
      priority: const [ringSource, _watch],
      workouts: workouts.take(limit).toList(),
    );
  }

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) async {
    if (fail) throw _readFailure;
    return workouts.where((w) => w.recordId == recordId).firstOrNull;
  }
}

final class _FailingRingStatus implements RingStatusReader {
  @override
  Future<RingStatus> status() async => throw _readFailure;
}

final DateTime _rideStart = workoutStart.subtract(const Duration(days: 1));

final _ride = ImportedWorkout(
  recordId: _importedId,
  source: _watch,
  type: WorkoutType.cycling,
  start: _rideStart,
  end: _rideStart.add(const Duration(minutes: 45)),
  utcOffset: Duration.zero,
);

class _RecentHost extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => AppPage(
    title: AppLocalizations.of(context).tabActivity,
    children: const [RecentWorkoutsCard()],
  );
}

typedef _Drive = Future<void> Function(WidgetTester tester, WorkoutRig rig);
typedef _Check = Future<void> Function(WidgetTester tester, AppLocalizations l);

final class _Case {
  const new(
    this.screen,
    this.expected, {
    this.rig,
    this.drive,
    this.ring,
    this.imported = const _Imported(),
    this.check,
  });

  final Widget screen;
  final Key? expected;
  final WorkoutRig Function()? rig;
  final _Drive? drive;
  final RingStatusReader Function()? ring;
  final ImportedWorkoutReader imported;
  final _Check? check;
}

WorkoutRig _saved({
  WorkoutType type = WorkoutType.running,
  WorkoutHealthStatus health = WorkoutHealthStatus.sent,
}) => WorkoutRig(
  store: MemoryWorkoutHistory(
    seed: [savedRun(type: type, health: health)],
  ),
);

WorkoutRig _failingRig() => WorkoutRig(store: _FailingHistory());

Future<void> _tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await settle(tester);
}

Future<void> _running(WidgetTester tester, WorkoutRig rig) =>
    startRunning(tester, rig);

Future<void> _finished(WidgetTester tester, WorkoutRig rig) async {
  await startRunning(tester, rig, seconds: 400);
  await finishWorkout(tester);
}

_Drive _heartLost(HeartRateProblem problem) => (tester, rig) async {
  await startRunning(tester, rig);
  rig.heartRate.fail(HeartRateUnavailable(problem));
  rig.run(15, bpm: null);
};

Future<void> _heartSilent(WidgetTester tester, WorkoutRig rig) async {
  await startRunning(tester, rig);
  rig.run(heartRateLostAfter.inSeconds, bpm: null);
}

_Drive _locationLost(LocationProblem problem) => (tester, rig) async {
  await workoutOf(tester).start(WorkoutType.walking, notice: testNotice);
  rig.location.fail(LocationUnavailable(problem));
  rig.run(30, meters: null);
};

Future<void> _expectText(WidgetTester tester, String text) async {
  await reveal(tester, find.text(text));
  expect(find.text(text), findsOneWidget);
}

Future<void> _expectLoadError(WidgetTester tester, AppLocalizations l) =>
    _expectText(tester, l.metricLoadError);

final _cases = <String, _Case>{
  'Pick': const _Case(WorkoutPickScreen(), WorkoutPickKeys.start),
  'Pick with swimming unavailable': _Case(
    const WorkoutPickScreen(),
    WorkoutPickKeys.swimming,
    check: (tester, l) => _expectText(tester, l.workoutSwimmingReason),
  ),
  'Pick without a ring': _Case(
    const WorkoutPickScreen(initialType: WorkoutType.other),
    WorkoutPickKeys.ring,
    ring: () => FakeRingStatusReader(RingStatus.unpaired),
    check: (tester, l) => _expectText(tester, l.workoutRingMissing),
  ),
  'Pick when the ring status cannot be read': _Case(
    const WorkoutPickScreen(),
    WorkoutPickKeys.start,
    ring: _FailingRingStatus.new,
    check: (tester, l) async =>
        expect(find.byKey(WorkoutPickKeys.ring), findsNothing),
  ),
  'Pick other with GPS on': _Case(
    const WorkoutPickScreen(initialType: WorkoutType.other),
    WorkoutPickKeys.gps,
    drive: (tester, rig) => _tap(tester, WorkoutPickKeys.gps),
  ),
  'Pick an indoor type': const _Case(
    WorkoutPickScreen(initialType: WorkoutType.stationaryBike),
    WorkoutPickKeys.detail,
  ),
  'Location before asking': const _Case(
    LocationPermissionScreen(type: WorkoutType.running),
    LocationPermissionKeys.allow,
  ),
  for (final status in LocationAccessStatus.values)
    'Location ${status.name}': _Case(
      LocationPermissionScreen(
        type: WorkoutType.running,
        initialStatus: status,
      ),
      LocationPermissionKeys.outcome,
    ),
  'Location that the phone cannot check': _Case(
    const LocationPermissionScreen(type: WorkoutType.running),
    LocationPermissionKeys.checkFailed,
    rig: () => WorkoutRig()..access.fail = true,
    drive: (tester, rig) => _tap(tester, LocationPermissionKeys.allow),
    check: (tester, l) async {
      await _expectText(tester, l.workoutLocationCheckFailedBody);
      expect(find.byKey(LocationPermissionKeys.retry), findsOneWidget);
      await reveal(tester, find.byKey(LocationPermissionKeys.withoutGps));
      expect(find.byKey(LocationPermissionKeys.withoutGps), findsOneWidget);
    },
  ),
  'Live without a workout': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.none,
    check: (tester, l) => _expectText(tester, l.workoutNoneBody),
  ),
  'Live running': const _Case(
    LiveWorkoutScreen(),
    LiveWorkoutKeys.toggle,
    drive: _running,
  ),
  'Live paused': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.toggle,
    drive: (tester, rig) async {
      await startRunning(tester, rig);
      workoutOf(tester).pause();
    },
  ),
  'Live confirm': const _Case(
    LiveWorkoutScreen(initialConfirming: true),
    LiveWorkoutKeys.confirm,
    drive: _running,
  ),
  'Live confirm indoor': _Case(
    const LiveWorkoutScreen(initialConfirming: true),
    LiveWorkoutKeys.confirm,
    drive: (tester, rig) =>
        startRunning(tester, rig, type: WorkoutType.strength, seconds: 60),
  ),
  'Live saved': const _Case(
    LiveWorkoutScreen(),
    LiveWorkoutKeys.saved,
    drive: _finished,
  ),
  'Live save failed': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.failed,
    rig: () => WorkoutRig(store: FlakyWorkoutStore(RecordingWorkoutStore())),
    drive: _finished,
    check: (tester, l) async =>
        expect(find.byKey(LiveWorkoutKeys.retry), findsOneWidget),
  ),
  'Live discarded': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.discarded,
    drive: (tester, rig) async {
      await startRunning(tester, rig);
      await discardWorkout(tester);
    },
  ),
  'Live without a GPS fix': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.gps,
    drive: (tester, rig) async {
      await workoutOf(tester).start(WorkoutType.running, notice: testNotice);
      rig.run(20, meters: null);
    },
    check: (tester, l) => _expectText(tester, l.workoutMapEmpty),
  ),
  'Live without heart rate yet': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.zoneCaption,
    drive: (tester, rig) async {
      await workoutOf(tester).start(WorkoutType.running, notice: testNotice);
      rig.run(20, bpm: null);
    },
    check: (tester, l) => _expectText(tester, l.workoutHeartWaiting),
  ),
  for (final problem in HeartRateProblem.values)
    'Live with the ring ${problem.name} mid workout': _Case(
      const LiveWorkoutScreen(),
      LiveWorkoutKeys.heart,
      drive: _heartLost(problem),
      check: (tester, l) async {
        expect(find.textContaining('HeartRateUnavailable'), findsNothing);
        expect(
          find.byKey(LiveWorkoutKeys.reconnect),
          problem == HeartRateProblem.noRing ? findsNothing : findsOneWidget,
        );
      },
    ),
  'Live with heart rate lost after a silence': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.link,
    drive: _heartSilent,
    check: (tester, l) async {
      await _expectText(tester, l.workoutLinkHeartRateLost);
      await _expectText(tester, l.workoutHeartStalled);
      await reveal(tester, find.byKey(LiveWorkoutKeys.reconnect));
      expect(find.byKey(LiveWorkoutKeys.reconnect), findsOneWidget);
    },
  ),
  'Live reconnecting after heart rate was lost': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.heart,
    drive: (tester, rig) async {
      await _heartSilent(tester, rig);
      await _tap(tester, LiveWorkoutKeys.reconnect);
      await flushStreams(tester);
    },
    check: (tester, l) async {
      expect(find.byKey(LiveWorkoutKeys.reconnect), findsNothing);
      expect(find.text(l.workoutHeartStalled), findsNothing);
    },
  ),
  for (final problem in LocationProblem.values)
    'Live with location ${problem.name}': _Case(
      const LiveWorkoutScreen(),
      LiveWorkoutKeys.gpsProblem,
      drive: _locationLost(problem),
      check: (tester, l) async {
        expect(find.textContaining('LocationUnavailable'), findsNothing);
        expect(
          find.byKey(LiveWorkoutKeys.settings),
          problem == LocationProblem.failed ? findsNothing : findsOneWidget,
        );
        await _expectText(
          tester,
          problem == LocationProblem.failed
              ? l.workoutGpsLost
              : l.workoutGpsOff,
        );
        await reveal(tester, find.byKey(LiveWorkoutKeys.gpsRetry));
        expect(find.byKey(LiveWorkoutKeys.gpsRetry), findsOneWidget);
      },
    ),
  'Live trying the GPS again': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.metrics,
    drive: (tester, rig) async {
      await _locationLost(LocationProblem.failed)(tester, rig);
      await _tap(tester, LiveWorkoutKeys.gpsRetry);
      await flushStreams(tester);
      rig.run(5);
    },
    check: (tester, l) async {
      final state = workoutContainer(tester).read(workoutProvider);
      expect(state.locationProblem, isNull);
      expect(state.snapshot?.trackPoints, 5);
    },
  ),
  'Live indoor without a profile': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.metrics,
    rig: () => WorkoutRig(profile: null),
    drive: (tester, rig) =>
        startRunning(tester, rig, type: WorkoutType.other, seconds: 60),
  ),
  'Live cycling': _Case(
    const LiveWorkoutScreen(),
    LiveWorkoutKeys.metrics,
    drive: (tester, rig) =>
        startRunning(tester, rig, type: WorkoutType.cycling, seconds: 60),
  ),
  'Summary without a workout': _Case(
    const WorkoutSummaryScreen(),
    WorkoutSummaryKeys.none,
    check: (tester, l) => _expectText(tester, l.workoutChoose),
  ),
  'Summary after a run': const _Case(
    WorkoutSummaryScreen(),
    WorkoutSummaryKeys.zones,
    drive: _finished,
  ),
  'Summary after a run that was not saved': _Case(
    const WorkoutSummaryScreen(),
    WorkoutSummaryKeys.retry,
    rig: () => WorkoutRig(store: FlakyWorkoutStore(RecordingWorkoutStore())),
    drive: _finished,
  ),
  'Summary of a cycling ride without a route': _Case(
    const WorkoutSummaryScreen(),
    WorkoutSummaryKeys.noRoute,
    drive: (tester, rig) async {
      await workoutOf(tester).start(WorkoutType.cycling, notice: testNotice);
      rig.run(120, meters: null);
      await finishWorkout(tester);
    },
  ),
  for (final health in WorkoutHealthStatus.values)
    'Saved summary ${health.name}': _Case(
      const WorkoutSummaryScreen(workoutId: savedRunId),
      WorkoutSummaryKeys.splits,
      rig: () => _saved(health: health),
    ),
  'Saved indoor summary': _Case(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    WorkoutSummaryKeys.pauses,
    rig: () => _saved(type: WorkoutType.yoga),
  ),
  'Saved summary confirming delete': _Case(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    WorkoutSummaryKeys.deleteConfirm,
    rig: _saved,
    drive: (tester, rig) => _tap(tester, WorkoutSummaryKeys.delete),
  ),
  'Saved summary deleted': _Case(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    WorkoutSummaryKeys.deleted,
    rig: _saved,
    drive: (tester, rig) async {
      await _tap(tester, WorkoutSummaryKeys.delete);
      await _tap(tester, WorkoutSummaryKeys.deleteConfirm);
    },
  ),
  'Saved summary whose delete failed': _Case(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    WorkoutSummaryKeys.deleteFailed,
    rig: () => WorkoutRig(
      store: MemoryWorkoutHistory(seed: [savedRun()])..failDelete = true,
    ),
    drive: (tester, rig) async {
      await _tap(tester, WorkoutSummaryKeys.delete);
      await _tap(tester, WorkoutSummaryKeys.deleteConfirm);
    },
  ),
  'Saved summary whose GPX export failed': _Case(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    WorkoutSummaryKeys.exportFailed,
    rig: () => _saved()..exporter.fail = true,
    drive: (tester, rig) => _tap(tester, WorkoutSummaryKeys.exportGpx),
  ),
  'Saved summary whose CSV export failed': _Case(
    const WorkoutSummaryScreen(workoutId: savedRunId),
    WorkoutSummaryKeys.exportFailed,
    rig: () => _saved()..exporter.fail = true,
    drive: (tester, rig) => _tap(tester, WorkoutSummaryKeys.exportCsv),
  ),
  'Summary of a missing workout': _Case(
    const WorkoutSummaryScreen(workoutId: 99),
    WorkoutSummaryKeys.none,
    check: (tester, l) => _expectText(tester, l.workoutSummaryMissing),
  ),
  'Summary that cannot be read': const _Case(
    WorkoutSummaryScreen(workoutId: savedRunId),
    null,
    rig: _failingRig,
    check: _expectLoadError,
  ),
  'Imported summary': _Case(
    const ImportedWorkoutScreen(recordId: _importedId),
    ImportedWorkoutKeys.source,
    imported: _Imported(workouts: [_ride]),
  ),
  'Imported summary no longer stored': const _Case(
    ImportedWorkoutScreen(recordId: _importedId),
    ImportedWorkoutKeys.missing,
  ),
  'Imported summary that cannot be read': const _Case(
    ImportedWorkoutScreen(recordId: _importedId),
    null,
    imported: _Imported(fail: true),
    check: _expectLoadError,
  ),
  'Recent workouts': _Case(
    const _RecentHost(),
    RecentWorkoutsKeys.importedItem(_importedId),
    rig: _saved,
    imported: _Imported(workouts: [_ride]),
    check: (tester, l) async =>
        expect(find.byKey(RecentWorkoutsKeys.item(savedRunId)), findsOneWidget),
  ),
  'Recent workouts before the first one': _Case(
    const _RecentHost(),
    RecentWorkoutsKeys.empty,
    check: (tester, l) =>
        _expectText(tester, l.workoutRecentEmptyHint(l.workoutStart)),
  ),
  'Recent workouts that cannot be read': const _Case(
    _RecentHost(),
    RecentWorkoutsKeys.error,
    rig: _failingRig,
    check: _expectLoadError,
  ),
};

Future<void> _pumpIn(
  WidgetTester tester,
  Locale locale,
  _Case c,
  WorkoutRig rig,
) => pumpScaled(
  tester,
  screenHost(c.screen),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: locale,
  overrides: <Override>[
    ...protocolLabOverrides(),
    ...ringOverrides(),
    ...rig.overrides(),
    ringStatusReaderProvider.overrideWithValue(
      c.ring?.call() ?? FakeRingStatusReader(pairedRing),
    ),
    importedWorkoutReaderProvider.overrideWithValue(c.imported),
  ],
);

void main() {
  test('the workout screens are checked in all 11 locales', () {
    expect(AppLocales.supported, hasLength(11));
  });

  for (final locale in AppLocales.supported) {
    group('$locale', () {
      final l10n = lookupAppLocalizations(locale);

      for (final MapEntry(key: name, value: c) in _cases.entries) {
        testWidgets('$name lays out without overflow or exception', (
          tester,
        ) async {
          final rig = c.rig?.call() ?? WorkoutRig();
          await _pumpIn(tester, locale, c, rig);
          expect(tester.takeException(), isNull);

          await expectNoLayoutOverflow(() async {
            await c.drive?.call(tester, rig);
            await tester.pumpAndSettle();
          });
          expect(tester.takeException(), isNull);
          expect(find.byWidget(c.screen), findsOneWidget);

          final expected = c.expected;
          if (expected != null) {
            await reveal(tester, find.byKey(expected));
            expect(find.byKey(expected), findsOneWidget);
          }
          await c.check?.call(tester, l10n);
          expect(tester.takeException(), isNull);

          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }
}
