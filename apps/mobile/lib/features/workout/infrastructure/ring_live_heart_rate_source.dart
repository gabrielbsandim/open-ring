import 'dart:async';

import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:ring_driver/ring_driver.dart';

const workoutLockRenewal = Duration(minutes: 5);

Stream<void> _everyLockRenewal() => Stream<void>.periodic(workoutLockRenewal);

final class RingLiveHeartRateSource implements LiveHeartRateSource {
  const new({
    required this.driver,
    required this.store,
    required this.lock,
    required this.clock,
    this.lockTimeout = SyncPairedRing.defaultLockTimeout,
    this.connectTimeout = const Duration(seconds: 20),
    this.renewals = _everyLockRenewal,
    this.newOwner = randomLockOwner,
  });

  final SmartRingDriver driver;
  final SyncStore store;
  final SyncLock lock;
  final DateTime Function() clock;
  final Duration lockTimeout;
  final Duration connectTimeout;
  final Stream<void> Function() renewals;
  final String Function() newOwner;

  @override
  Stream<int> bpm() {
    late final StreamController<int> controller;
    late final _Link link;
    controller = StreamController<int>(
      onListen: () {
        link = _Link(this, controller, newOwner());
        unawaited(link.open());
      },
      onPause: () => link.pause(),
      onResume: () => link.resume(),
      onCancel: () => link.close(),
    );
    return controller.stream;
  }
}

final class _Link {
  new(this.source, this.controller, this.owner);

  final RingLiveHeartRateSource source;
  final StreamController<int> controller;
  final String owner;

  StreamSubscription<LiveReading>? _live;
  StreamSubscription<void>? _renewals;
  bool _locked = false;
  bool _connected = false;
  bool _streaming = false;
  bool _closed = false;
  bool _ready = false;
  bool _paused = false;
  Future<void>? _stopping;

  Future<void> open() async {
    final problem = await _connect();
    if (_closed) {
      await _teardown();
      return;
    }
    if (problem != null) return _fail(problem);
    _ready = true;
    if (!_paused) _stream();
    _renewals = source.renewals().listen((_) => unawaited(_renew()));
  }

  void _stream() {
    _streaming = true;
    _live = source.driver.startHeartRateStream().listen(
      (reading) => controller.add(reading.value),
      onError: (Object _) => _fail(HeartRateProblem.unreachable),
    );
  }

  // A paused workout keeps the link and the lock, but the ring's sensor is
  // the battery cost, so the stream itself stops until resume.
  void pause() {
    _paused = true;
    final live = _live;
    if (_closed || live == null) return;
    _live = null;
    _streaming = false;
    _stopping = _stopStream(live);
  }

  Future<void> _stopStream(StreamSubscription<LiveReading> live) async {
    await live.cancel();
    await _quietly(source.driver.stopHeartRateStream);
  }

  void resume() {
    _paused = false;
    unawaited(_restart());
  }

  Future<void> _restart() async {
    await _stopping;
    if (_closed || _paused || !_ready || _live != null) return;
    _stream();
  }

  Future<HeartRateProblem?> _connect() async {
    try {
      final ring = await source.store.pairedRing();
      if (ring == null) return HeartRateProblem.noRing;
      _locked = await source.lock.acquire(
        owner,
        at: source.clock(),
        timeout: source.lockTimeout,
      );
      if (!_locked) return HeartRateProblem.busy;
      if (_closed) return null;
      _connected = true;
      await source.driver.connect(ring.deviceId).timeout(source.connectTimeout);
      return null;
    } on Object {
      return HeartRateProblem.unreachable;
    }
  }

  // The lock has no same-owner renewal, and a workout outlives its timeout,
  // so the link gives it back and takes it again before it expires.
  Future<void> _renew() async {
    if (_closed || !_locked) return;
    await _quietly(() => source.lock.release(owner));
    try {
      _locked = await source.lock.acquire(
        owner,
        at: source.clock(),
        timeout: source.lockTimeout,
      );
    } on Object {
      _locked = false;
    }
  }

  void _fail(HeartRateProblem problem) {
    if (_closed) return;
    controller.addError(HeartRateUnavailable(problem));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _teardown();
  }

  Future<void> _teardown() async {
    await _renewals?.cancel();
    await _stopping;
    await _live?.cancel();
    if (_streaming) await _quietly(source.driver.stopHeartRateStream);
    if (_connected) await _quietly(source.driver.disconnect);
    if (_locked) await _quietly(() => source.lock.release(owner));
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Teardown runs after the outcome is known and must not replace it.
    }
  }
}
