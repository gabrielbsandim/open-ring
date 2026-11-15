import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/application/logged_weight.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_notice.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/location_fix.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

const workoutTick = Duration(seconds: 1);

// The ring streams a reading every second, so this long without one is a
// dropped link rather than a slow sensor.
const heartRateLostAfter = Duration(seconds: 30);

final locationSourceProvider = Provider<LocationSource>(
  (ref) => throw UnimplementedError('Override locationSourceProvider.'),
);

final liveHeartRateSourceProvider = Provider<LiveHeartRateSource>(
  (ref) => throw UnimplementedError('Override liveHeartRateSourceProvider.'),
);

final workoutStoreProvider = Provider<WorkoutStore>(
  (ref) => throw UnimplementedError('Override workoutStoreProvider.'),
);

final workoutNotifierProvider = Provider<WorkoutNotifier>(
  (ref) => InMemoryWorkoutNotifier(),
);

final workoutTicksProvider = Provider<Stream<void> Function()>(
  (ref) =>
      () => Stream<void>.periodic(workoutTick),
);

final workoutProvider = NotifierProvider<WorkoutController, WorkoutState>(
  WorkoutController.new,
);

const _minZoneMax = 100;
const _maxZoneMax = 250;

WorkoutProfile workoutProfileOf(
  UserProfile? profile, {
  required int year,
  double? loggedKilograms,
}) => WorkoutProfile(
  zones: profile == null ? null : _zonesOf(profile, year),
  weightKilograms: loggedKilograms ?? profile?.weightKilograms,
);

HeartRateZones? _zonesOf(UserProfile profile, int year) {
  final max = profile.maxHeartRate ?? _ageMax(profile.ageIn(year));
  if (max == null || max < _minZoneMax || max > _maxZoneMax) return null;
  return HeartRateZones(maxHeartRate: max);
}

int? _ageMax(int? age) {
  if (age == null || age < 1 || age > 119) return null;
  return maxHeartRateForAge(age);
}

class WorkoutController extends Notifier<WorkoutState> {
  WorkoutSession? _session;
  StreamSubscription<void>? _ticks;
  StreamSubscription<int>? _heartRate;
  StreamSubscription<LocationFix>? _location;
  StreamSubscription<WorkoutNoticeAction>? _actions;
  WorkoutNotice? _shown;
  WorkoutNotifier? _showing;
  Future<void>? _heartRateStopping;
  Future<void>? _locationStopping;
  LocationNotice? _notice;
  DateTime? _lastBeat;
  bool _starting = false;
  bool _restartingHeartRate = false;
  bool _restartingLocation = false;

  WorkoutSession? get session => _session;

  @override
  WorkoutState build() {
    ref.onDispose(() {
      unawaited(_stopStreams());
      final showing = _showing;
      if (showing != null) unawaited(_quietly(_guarded(showing.hide)));
    });
    return const WorkoutState();
  }

  Future<void> start(
    WorkoutType type, {
    required LocationNotice notice,
    bool? gps,
  }) async {
    if (_starting || state.live) return;
    _starting = true;
    final profile = await _profile();
    _starting = false;
    if (!ref.mounted) return;
    final session = WorkoutSession(
      type: type,
      profile: profile,
      gps: gps,
      heartRateHold: heartRateLostAfter,
    )..start(_now());
    _session = session;
    _notice = notice;
    _shown = null;
    state = WorkoutState(snapshot: session.snapshotAt(_now()));
    _actions = ref.read(workoutNotifierProvider).actions.listen(_onAction);
    _showNotice(session);
    _listenHeartRate(session);
    if (session.gps) _listenLocation(session, notice);
    _ticks = ref.read(workoutTicksProvider)().listen((_) => _tick(session));
  }

  Future<void> reconnectHeartRate() async {
    final session = _session;
    if (session == null || !state.live || _restartingHeartRate) return;
    _restartingHeartRate = true;
    session.heartRateLinkStart = _now();
    state = state.withHeartRateRestarted().next(
      snapshot: session.snapshotAt(_now()),
    );
    final stopping = [_heartRateStopping, _heartRate?.cancel()];
    _heartRate = null;
    _heartRateStopping = null;
    await Future.wait(stopping.map(_quietly));
    _restartingHeartRate = false;
    if (!_current(session) || !state.live) return;
    _listenHeartRate(session);
  }

  Future<void> retryLocation() async {
    final session = _session;
    final notice = _notice;
    if (session == null || notice == null || !session.gps) return;
    if (!state.live || _restartingLocation) return;
    _restartingLocation = true;
    state = state.withLocationRestarted();
    final stopping = [_locationStopping, _location?.cancel()];
    _location = null;
    _locationStopping = null;
    await Future.wait(stopping.map(_quietly));
    _restartingLocation = false;
    if (!_current(session) || !state.live) return;
    _listenLocation(session, notice);
  }

  void pause() {
    final session = _session;
    if (session == null || session.status != WorkoutStatus.running) return;
    session.pause(_now());
    _heartRate?.pause();
    _publish(session);
  }

  void resume() {
    final session = _session;
    if (session == null || session.status != WorkoutStatus.paused) return;
    session.resume(_now());
    _lastBeat = _now();
    _heartRate?.resume();
    _publish(session);
  }

  Future<void> finish() async {
    final session = _session;
    if (session == null || !state.live) return;
    session.finish(_now());
    _publish(session);
    await _stopStreams();
    await _hideNotice();
    await _save(session);
  }

  Future<void> saveAgain() async {
    final session = _session;
    if (session == null || state.save != WorkoutSave.failed) return;
    await _save(session);
  }

  void forgetSaved(int workoutId) {
    if (state.live || state.workoutId != workoutId) return;
    _session = null;
    state = const WorkoutState();
  }

  Future<void> discard() async {
    final session = _session;
    if (session == null || !state.live) return;
    session.discard(_now());
    _publish(session);
    await _stopStreams();
    await _hideNotice();
  }

  Future<void> _save(WorkoutSession session) async {
    state = state.next(save: WorkoutSave.saving);
    final workout = session.finished();
    try {
      final id = await ref.read(workoutStoreProvider).save(workout, at: _now());
      if (!ref.mounted || !identical(_session, session)) return;
      state = state.next(save: WorkoutSave.saved, workoutId: id);
      ref.read(dataRevisionProvider.notifier).bump();
    } on Object {
      if (!ref.mounted || !identical(_session, session)) return;
      state = state.next(save: WorkoutSave.failed);
    }
  }

  void _listenHeartRate(WorkoutSession session) {
    _lastBeat = _now();
    _heartRate = ref
        .read(liveHeartRateSourceProvider)
        .bpm()
        .listen(
          (bpm) => _onHeartRate(session, bpm),
          onError: (Object error) => _onHeartRateError(session, error),
          onDone: () => _onHeartRateError(
            session,
            const HeartRateUnavailable(HeartRateProblem.unreachable),
          ),
        );
    if (session.status == WorkoutStatus.paused) _heartRate?.pause();
  }

  void _listenLocation(WorkoutSession session, LocationNotice notice) {
    _location = ref
        .read(locationSourceProvider)
        .fixes(notice)
        .listen(
          (fix) => _onFix(session, fix),
          onError: (Object error) => _onLocationError(session, error),
          onDone: () => _onLocationError(
            session,
            const LocationUnavailable(LocationProblem.failed),
          ),
        );
  }

  void _onHeartRate(WorkoutSession session, int bpm) {
    if (!_current(session)) return;
    final now = _now();
    session.addHeartRate(bpm, now);
    if (bpm < minWorkoutHeartRate || bpm > maxWorkoutHeartRate) return;
    _lastBeat = now;
    if (state.heartRateStalled) state = state.next(heartRateStalled: false);
  }

  void _tick(WorkoutSession session) {
    _checkHeartRate(session);
    _publish(session);
  }

  void _checkHeartRate(WorkoutSession session) {
    final lastBeat = _lastBeat;
    if (!_current(session) || _heartRate == null || lastBeat == null) return;
    if (session.status != WorkoutStatus.running) return;
    if (state.heartRateStalled) return;
    if (_now().difference(lastBeat) < heartRateLostAfter) return;
    state = state.next(heartRateStalled: true);
  }

  void _onFix(WorkoutSession session, LocationFix fix) {
    if (!identical(_session, session)) return;
    session.addFix(fix);
  }

  void _onHeartRateError(WorkoutSession session, Object error) {
    if (!_current(session)) return;
    final problem = error is HeartRateUnavailable
        ? error.problem
        : HeartRateProblem.unreachable;
    state = state.next(heartRateProblem: problem, heartRateStalled: false);
    _heartRateStopping = _quietly(_heartRate?.cancel());
    _heartRate = null;
  }

  void _onLocationError(WorkoutSession session, Object error) {
    if (!_current(session)) return;
    final problem = error is LocationUnavailable
        ? error.problem
        : LocationProblem.failed;
    state = state.next(locationProblem: problem);
    _locationStopping = _quietly(_location?.cancel());
    _location = null;
  }

  void _publish(WorkoutSession session) {
    if (!_current(session)) return;
    state = state.next(snapshot: session.snapshotAt(_now()));
    _showNotice(session);
  }

  void _onAction(WorkoutNoticeAction action) => switch (action) {
    WorkoutNoticeAction.pause => pause(),
    WorkoutNoticeAction.resume => resume(),
    WorkoutNoticeAction.stop => unawaited(finish()),
  };

  void _showNotice(WorkoutSession session) {
    final labels = _notice;
    final snapshot = state.snapshot;
    if (labels == null || snapshot == null || !state.live) return;
    final notice = workoutNoticeOf(
      snapshot,
      labels,
      ref.read(currentUnitSystemProvider),
    );
    if (notice == _shown) return;
    _shown = notice;
    final notifier = _notifier;
    _showing = notifier;
    unawaited(_quietly(_guarded(() => notifier.show(notice))));
  }

  Future<void> _hideNotice() {
    _shown = null;
    _showing = null;
    return _quietly(_guarded(_notifier.hide));
  }

  WorkoutNotifier get _notifier => ref.read(workoutNotifierProvider);

  // A notifier that throws before returning its future must not stop a workout.
  static Future<void> _guarded(Future<void> Function() call) async =>
      await call();

  bool _current(WorkoutSession session) =>
      ref.mounted && identical(_session, session);

  Future<void> _stopStreams() async {
    final cancels = [
      _quietly(_actions?.cancel()),
      _quietly(_ticks?.cancel()),
      _quietly(_heartRate?.cancel()),
      _quietly(_location?.cancel()),
      _quietly(_heartRateStopping),
      _quietly(_locationStopping),
    ];
    _actions = null;
    _ticks = null;
    _heartRate = null;
    _location = null;
    _heartRateStopping = null;
    _locationStopping = null;
    await Future.wait(cancels);
  }

  Future<WorkoutProfile> _profile() async {
    final profile = await _orNull(
      () => ref.read(userProfileStoreProvider).read(),
    );
    final logged = await _orNull(() => ref.read(loggedWeightProvider.future));
    return workoutProfileOf(
      profile,
      year: _now().year,
      loggedKilograms: logged,
    );
  }

  Future<T?> _orNull<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  DateTime _now() => ref.read(clockProvider)();

  static Future<void> _quietly(Future<void>? cancel) async {
    try {
      await cancel;
    } on Object {
      // A source that fails while stopping has nothing left to record.
    }
  }
}
