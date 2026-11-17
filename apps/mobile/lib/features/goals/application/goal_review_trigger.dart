import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/goals/application/goal_reviewer.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';

/// Runs a pass when Goals turns on, when the data or the date changes and
/// when the app comes back to the foreground.
final goalReviewTriggerProvider = Provider<GoalReviewTrigger>((ref) {
  final trigger = GoalReviewTrigger(
    // Demo history sits in the same tables as the real one, so a pass in demo
    // mode would review the real goal against demo data.
    enabled: () =>
        ref.mounted &&
        !ref.read(demoModeProvider) &&
        ref.read(goalsEnabledProvider),
    startDueBlock: () =>
        ref.read(goalReviewerProvider.notifier).startDueBlock(),
    reviewDueWeek: () =>
        ref.read(goalReviewerProvider.notifier).reviewDueWeek(),
    mayReview: () async {
      final ring = await ref.read(syncStoreProvider).pairedRing();
      return reviewMayRun(
        now: ref.read(clockProvider)(),
        lastSyncAt: ring?.lastSyncAt,
      );
    },
    onError: (error) {
      if (!ref.mounted) return;
      debugPrint('Goal review pass failed: $error');
    },
  );
  // The day is checked first, so a pass never works on yesterday's date.
  void pass() {
    if (!ref.mounted) return;
    ref.read(dayRollProvider).check();
    unawaited(trigger.run());
  }

  ref
    ..listen(goalsEnabledProvider, (_, enabled) {
      if (enabled) pass();
    }, fireImmediately: true)
    ..listen(dataRevisionProvider, (_, _) => pass())
    ..listen(currentDateProvider, (_, _) => pass());
  final listener = AppLifecycleListener(onResume: pass);
  ref.onDispose(listener.dispose);
  return trigger;
});

/// Whether the review of the closed week may run now. On a Monday it waits
/// for a ring sync of that day, so the Sunday it reviews has arrived.
bool reviewMayRun({required DateTime now, required DateTime? lastSyncAt}) {
  if (now.weekday != DateTime.monday) return true;
  if (lastSyncAt == null) return false;
  final today = LocalDate.fromInstant(now, now.timeZoneOffset);
  return !lastSyncAt.isBefore(localMidnight(today, now.timeZoneOffset));
}

/// One pass starts a due block, then writes a due review. A call during a
/// pass asks for one more pass instead of running beside it, and a pass stops
/// before its next step once the trigger is no longer enabled.
final class GoalReviewTrigger {
  new({
    required this.enabled,
    required this.startDueBlock,
    required this.reviewDueWeek,
    required this.mayReview,
    required this.onError,
  });

  final bool Function() enabled;
  final Future<bool> Function() startDueBlock;
  final Future<Review?> Function() reviewDueWeek;
  final Future<bool> Function() mayReview;
  final void Function(Object error) onError;

  var _running = false;
  var _again = false;

  Future<void> run() async {
    if (!enabled()) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _pass();
      } while (_again && enabled());
    } finally {
      _running = false;
    }
  }

  Future<void> _pass() async {
    await _guarded(startDueBlock);
    if (!enabled()) return;
    final may = await _guarded(mayReview) ?? false;
    if (!may || !enabled()) return;
    await _guarded(reviewDueWeek);
  }

  // A step that fails is reported and the pass goes on: a source that cannot
  // be read must not take the app down, nor block the other step.
  Future<T?> _guarded<T>(Future<T> Function() step) async {
    try {
      return await step();
    } on Object catch (error) {
      onError(error);
      return null;
    }
  }
}
