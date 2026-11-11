import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_outbox_store.dart';

final class FakeDeadOutboxStore implements DeadOutboxStore {
  new([Map<HealthRecordKind, String?> dead = const {}]) : dead = {...dead};

  final Map<HealthRecordKind, String?> dead;
  final List<HealthRecordKind?> resets = [];

  @override
  Future<Map<HealthRecordKind, String?>> lastDeadErrors() async => {...dead};

  @override
  Future<int> resetDead({HealthRecordKind? kind}) async {
    resets.add(kind);
    final kinds = kind == null ? {...dead.keys} : {kind};
    final hit = kinds.where(dead.containsKey).length;
    dead.removeWhere((k, _) => kinds.contains(k));
    return hit;
  }
}
