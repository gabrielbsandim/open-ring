import 'package:meta/meta.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:ring_driver/ring_driver.dart';

enum SyncRunOutcome { completed, partial, unreachable, stopped }

@immutable
final class SyncRun {
  const new({
    required this.at,
    required this.outcome,
    this.kinds = const {},
    this.recordCount = 0,
    this.battery,
    this.failures = const {},
    this.heartRateIntervalSeen,
  });

  final DateTime at;
  final SyncRunOutcome outcome;
  final Set<RecordKind> kinds;
  final int recordCount;
  final BatteryStatus? battery;
  final Set<RingCapability> failures;

  // What the ring reported before the sync aligned it, Duration.zero when off,
  // so another app changing the interval between syncs shows up.
  final Duration? heartRateIntervalSeen;

  bool get failed =>
      outcome == SyncRunOutcome.unreachable ||
      outcome == SyncRunOutcome.stopped;
}
