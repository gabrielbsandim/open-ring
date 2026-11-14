import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

final resumeSyncTriggerProvider = Provider<ResumeSyncTrigger>((ref) {
  final trigger = ResumeSyncTrigger(
    pairedRing: () => ref.read(syncStoreProvider).pairedRing(),
    readsEnabled: () => ref.read(anyHealthReadEnabledProvider.future),
    sync: () => ref.read(ringSyncProvider.notifier).autoSync(),
    clock: ref.watch(syncClockProvider),
  );
  final listener = AppLifecycleListener(
    onResume: () => unawaited(trigger.onForeground()),
  );
  ref.onDispose(listener.dispose);
  return trigger;
});

final class ResumeSyncTrigger {
  new({
    required this.pairedRing,
    required this.readsEnabled,
    required this.sync,
    required this.clock,
    this.minimumInterval = defaultMinimumInterval,
  });

  static const defaultMinimumInterval = Duration(minutes: 15);

  final Future<PairedRing?> Function() pairedRing;
  final Future<bool> Function() readsEnabled;
  final Future<void> Function() sync;
  final DateTime Function() clock;
  final Duration minimumInterval;

  DateTime? _lastAttempt;

  Future<void> onForeground() async {
    final now = clock();
    if (_isRecent(_lastAttempt, now)) return;
    _lastAttempt = now;
    final ring = await pairedRing();
    if (ring == null) {
      await _importWithoutRing();
      return;
    }
    if (_isRecent(ring.lastSyncAt, now)) return;
    await sync();
  }

  Future<void> _importWithoutRing() async {
    if (!await readsEnabled()) return;
    await sync();
  }

  bool _isRecent(DateTime? at, DateTime now) =>
      at != null && now.difference(at) < minimumInterval;
}
