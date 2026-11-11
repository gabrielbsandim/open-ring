import 'package:meta/meta.dart';
import 'package:open_ring/core/records/health_record_kind.dart';

@immutable
final class OutboxSummary {
  new({
    Map<HealthRecordKind, int> pendingRecords = const {},
    Map<HealthRecordKind, int> disabledRecords = const {},
    this.pendingRows = 0,
    this.deadRows = 0,
    this.lastDeadError,
    this.oldestPendingAt,
    this.lastSentAt,
  }) : pendingRecords = Map.unmodifiable(pendingRecords),
       disabledRecords = Map.unmodifiable(disabledRecords);

  final Map<HealthRecordKind, int> pendingRecords;
  final Map<HealthRecordKind, int> disabledRecords;
  final int pendingRows;
  final int deadRows;
  final String? lastDeadError;
  final DateTime? oldestPendingAt;
  final DateTime? lastSentAt;

  int get pendingRecordCount =>
      pendingRecords.values.fold(0, (sum, count) => sum + count);

  OutboxFailure get deadCause => OutboxFailure.of(lastDeadError);
}

enum OutboxFailure {
  permission,
  unavailable,
  rejected,
  unknown;

  // Matched on the stored error text, the only trace a dead row keeps; the
  // first pattern that appears wins.
  static const List<(String, OutboxFailure)> _patterns = [
    ('securityexception', OutboxFailure.permission),
    ('permission', OutboxFailure.permission),
    ('not authorized', OutboxFailure.permission),
    ('missingpluginexception', OutboxFailure.unavailable),
    ('remoteexception', OutboxFailure.unavailable),
    ('timeoutexception', OutboxFailure.unavailable),
    ('unavailable', OutboxFailure.unavailable),
    ('healthwriteexception', OutboxFailure.rejected),
  ];

  static OutboxFailure of(String? error) {
    final text = error?.toLowerCase();
    if (text == null) return OutboxFailure.unknown;
    for (final (pattern, failure) in _patterns) {
      if (text.contains(pattern)) return failure;
    }
    return OutboxFailure.unknown;
  }
}

abstract interface class OutboxSummaryReader {
  Future<OutboxSummary> summary();
}

abstract interface class HealthSettingsOpener {
  Future<void> open();
}
