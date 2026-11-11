import 'package:meta/meta.dart';
import 'package:open_ring/core/records/record_kind.dart';

enum SyncRunOutcome { completed, partial, unreachable, stopped }

@immutable
final class SyncRun {
  const new({
    required this.at,
    required this.outcome,
    this.kinds = const {},
    this.recordCount = 0,
  });

  final DateTime at;
  final SyncRunOutcome outcome;
  final Set<RecordKind> kinds;
  final int recordCount;

  bool get failed =>
      outcome == SyncRunOutcome.unreachable ||
      outcome == SyncRunOutcome.stopped;
}
