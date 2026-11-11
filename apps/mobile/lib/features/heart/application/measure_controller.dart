import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:open_ring/features/heart/domain/spot_reading_store.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

const minLiveHeartRate = 30;
const maxLiveHeartRate = 220;

final spotReadingStoreProvider = Provider<SpotReadingStore>(
  (ref) => throw UnimplementedError('Override spotReadingStoreProvider.'),
);

final measureTimingProvider = Provider<MeasureTiming>(
  (ref) => const MeasureTiming(),
);

final NotifierProvider<MeasureController, MeasureState> measureProvider =
    NotifierProvider.autoDispose<MeasureController, MeasureState>(
      MeasureController.new,
    );

bool plausibleLiveReading(LiveReading reading) => switch (reading.kind) {
  LiveKind.heartRate =>
    reading.value >= minLiveHeartRate && reading.value <= maxLiveHeartRate,
  LiveKind.spo2 => reading.value >= spo2MinPlausible && reading.value <= 100,
};

LiveReading? spotResult(List<LiveReading> readings) {
  if (readings.isEmpty) return null;
  final values = [for (final r in readings) r.value]..sort();
  final middle = values.length ~/ 2;
  final median = values.length.isOdd
      ? values[middle]
      : ((values[middle - 1] + values[middle]) / 2).round();
  return LiveReading(
    kind: readings.last.kind,
    value: median,
    at: readings.last.at,
  );
}

class MeasureController extends Notifier<MeasureState> {
  _Session? _session;

  @override
  MeasureState build() {
    ref.onDispose(_dispose);
    return MeasureState(window: ref.read(measureTimingProvider).window);
  }

  void choose(LiveKind kind) {
    if (state.running) return;
    state = MeasureState(kind: kind, window: state.window);
  }

  Future<void> start() async {
    if (state.running) return;
    final timing = ref.read(measureTimingProvider);
    final session = _Session(
      kind: state.kind,
      driver: ref.read(smartRingDriverProvider),
      lock: ref.read(syncLockProvider),
      clock: ref.read(syncClockProvider),
    );
    _session = session;
    state = MeasureState(
      kind: session.kind,
      phase: MeasurePhase.connecting,
      window: timing.window,
    );
    final failure = await session.open(
      ref.read(syncStoreProvider),
      timing.connectTimeout,
    );
    if (!identical(_session, session)) return await session.close();
    if (failure != null) return await _fail(session, failure);
    state = state.next(phase: MeasurePhase.searching);
    session
      ..listen(
        onReading: (reading) => _onReading(session, reading),
        onError: () => unawaited(_fail(session, MeasureFailure.unreachable)),
      )
      ..ticker = Timer.periodic(timing.tick, (_) => _onTick(session, timing));
  }

  Future<void> cancel() async {
    final session = _session;
    if (session == null) return;
    _session = null;
    state = MeasureState(
      kind: session.kind,
      window: state.window,
      cancelled: true,
    );
    await session.close();
  }

  void _onReading(_Session session, LiveReading reading) {
    if (!identical(_session, session) || !plausibleLiveReading(reading)) {
      return;
    }
    session.readings.add(reading);
    state = state.next(phase: MeasurePhase.reading, latest: reading.value);
  }

  void _onTick(_Session session, MeasureTiming timing) {
    if (!identical(_session, session)) return;
    final elapsed = state.elapsed + timing.tick;
    if (elapsed < timing.window) {
      state = state.next(elapsed: elapsed);
      return;
    }
    unawaited(_complete(session));
  }

  Future<void> _complete(_Session session) async {
    final reading = spotResult(session.readings);
    await session.close();
    if (!identical(_session, session)) return;
    if (reading == null) return await _fail(session, MeasureFailure.noReading);
    final saved = await _save(session, reading);
    if (!identical(_session, session)) return;
    _session = null;
    state = MeasureState(
      kind: session.kind,
      phase: MeasurePhase.done,
      window: state.window,
      elapsed: state.window,
      result: MeasureResult(reading: reading, saved: saved),
    );
    if (saved) ref.read(dataRevisionProvider.notifier).bump();
  }

  Future<bool> _save(_Session session, LiveReading reading) async {
    final deviceId = session.deviceId;
    if (deviceId == null) return false;
    try {
      await ref.read(spotReadingStoreProvider).save(deviceId, reading);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _fail(_Session session, MeasureFailure failure) async {
    await session.close();
    if (!identical(_session, session)) return;
    _session = null;
    state = MeasureState(
      kind: session.kind,
      phase: MeasurePhase.failed,
      window: state.window,
      failure: failure,
    );
  }

  void _dispose() {
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.close());
  }
}

final class _Session {
  new({
    required this.kind,
    required this.driver,
    required this.lock,
    required this.clock,
  });

  final LiveKind kind;
  final SmartRingDriver driver;
  final SyncLock lock;
  final DateTime Function() clock;
  final String owner = randomLockOwner();
  final readings = <LiveReading>[];

  String? deviceId;
  Timer? ticker;
  StreamSubscription<LiveReading>? _subscription;
  bool _locked = false;
  bool _connected = false;
  bool _live = false;
  bool _closed = false;

  Future<MeasureFailure?> open(SyncStore store, Duration connectTimeout) async {
    try {
      final ring = await store.pairedRing();
      if (ring == null) return MeasureFailure.noRing;
      deviceId = ring.deviceId;
      _locked = await lock.acquire(
        owner,
        at: clock(),
        timeout: SyncPairedRing.defaultLockTimeout,
      );
      if (!_locked) return MeasureFailure.busy;
      _connected = true;
      await driver.connect(ring.deviceId).timeout(connectTimeout);
      return null;
    } on Object {
      return MeasureFailure.unreachable;
    }
  }

  void listen({
    required void Function(LiveReading reading) onReading,
    required void Function() onError,
  }) {
    _live = true;
    _subscription = driver
        .startLive(kind)
        .listen(onReading, onError: (Object _) => onError());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ticker?.cancel();
    await _subscription?.cancel();
    if (_live) await _quietly(driver.stopLive);
    if (_connected) await _quietly(driver.disconnect);
    if (_locked) await _quietly(() => lock.release(owner));
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Teardown runs after the outcome is known and must not replace it.
    }
  }
}
