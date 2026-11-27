import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';

final dayTagStoreProvider = Provider<DayTagStore>(
  (ref) => InMemoryDayTagStore(),
);

final dayTagsProvider = FutureProvider<Map<LocalDate, DayTag>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(dayTagStoreProvider).all();
});

final dayTagLogProvider = NotifierProvider<DayTagLog, void>(DayTagLog.new);

class DayTagLog extends Notifier<void> {
  @override
  void build() {}

  /// Sets or, with null, clears the tag of a day. False when the day is
  /// outside the editable window or nothing changed.
  Future<bool> set(LocalDate date, DayTag? tag) async {
    final now = ref.read(clockProvider)();
    final today = LocalDate(now.year, now.month, now.day);
    if (!canEditDayTag(date, today: today)) return false;
    final store = ref.read(dayTagStoreProvider);
    final changed = tag == null
        ? await store.remove(date)
        : await store.put(date, tag, now: now);
    if (changed) ref.read(dataRevisionProvider.notifier).bump();
    return changed;
  }
}
