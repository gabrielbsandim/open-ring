import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';

final weighInStoreProvider = Provider<WeighInStore>(
  (ref) => InMemoryWeighInStore(),
);

final weighInsProvider = FutureProvider<List<WeighIn>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(weighInStoreProvider).all();
});

final weighInLogProvider = NotifierProvider<WeighInLog, void>(WeighInLog.new);

class WeighInLog extends Notifier<void> {
  @override
  void build() {}

  WeighInStore get _store => ref.read(weighInStoreProvider);

  Future<Set<WeighInIssue>> add(WeighInDraft draft) async {
    final issues = _issues(draft);
    if (issues.isNotEmpty) return issues;
    await _store.add(draft);
    _bump(changed: true);
    return issues;
  }

  Future<Set<WeighInIssue>> update(int id, WeighInDraft draft) async {
    final issues = _issues(draft);
    if (issues.isNotEmpty) return issues;
    _bump(changed: await _store.update(id, draft));
    return issues;
  }

  Future<void> delete(int id) async => _bump(changed: await _store.delete(id));

  Future<void> deleteAll() async =>
      _bump(changed: await _store.deleteAll() > 0);

  Set<WeighInIssue> _issues(WeighInDraft draft) =>
      draft.validate(now: ref.read(clockProvider)());

  void _bump({required bool changed}) {
    if (!changed) return;
    ref.read(dataRevisionProvider.notifier).bump();
  }
}
