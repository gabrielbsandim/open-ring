import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_outbox_store.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

final class RetryDeadHealthRows {
  const new({required this.outbox, required this.process});

  final DeadOutboxStore outbox;
  final Future<void> Function() process;

  Future<int> call({HealthRecordKind? kind}) async {
    final reset = await outbox.resetDead(kind: kind);
    if (reset > 0) await process();
    return reset;
  }

  Future<int> afterGrant() async {
    final errors = await outbox.lastDeadErrors();
    var reset = 0;
    for (final MapEntry(key: kind, value: error) in errors.entries) {
      if (OutboxFailure.of(error) != OutboxFailure.permission) continue;
      reset += await outbox.resetDead(kind: kind);
    }
    if (reset > 0) await process();
    return reset;
  }
}

final class HealthGrantWatch {
  Set<HealthRecordKind>? _missing;

  // True when a kind seen as missing is now granted. The first observation
  // only sets the baseline, so a grant from before this run never counts.
  bool observe(Map<HealthRecordKind, HealthAccess> access) {
    final before = _missing;
    _missing = {
      for (final MapEntry(key: kind, value: state) in access.entries)
        if (_isMissing(state)) kind,
    };
    if (before == null) return false;
    return before.any((kind) => access[kind] == HealthAccess.granted);
  }

  static bool _isMissing(HealthAccess state) =>
      state == HealthAccess.denied || state == HealthAccess.unavailable;
}
