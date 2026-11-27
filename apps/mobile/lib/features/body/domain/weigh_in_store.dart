import 'package:open_ring/features/body/domain/weigh_in.dart';

abstract interface class WeighInStore {
  Future<List<WeighIn>> all();

  Future<WeighIn> add(WeighInDraft draft);

  Future<bool> update(int id, WeighInDraft draft);

  Future<bool> delete(int id);

  Future<int> deleteAll();

  Future<int> count();
}

final class InMemoryWeighInStore implements WeighInStore {
  final Map<int, WeighIn> _rows = {};
  int _lastId = 0;

  @override
  Future<List<WeighIn>> all() async =>
      _rows.values.toList()..sort(_newestFirst);

  @override
  Future<WeighIn> add(WeighInDraft draft) async =>
      _rows[_lastId + 1] = _row(_lastId += 1, draft);

  @override
  Future<bool> update(int id, WeighInDraft draft) async {
    if (!_rows.containsKey(id)) return false;
    _rows[id] = _row(id, draft);
    return true;
  }

  @override
  Future<bool> delete(int id) async => _rows.remove(id) != null;

  @override
  Future<int> deleteAll() async {
    final removed = _rows.length;
    _rows.clear();
    return removed;
  }

  @override
  Future<int> count() async => _rows.length;

  static int _newestFirst(WeighIn a, WeighIn b) {
    final byTime = b.at.compareTo(a.at);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  static WeighIn _row(int id, WeighInDraft draft) => WeighIn(
    id: id,
    at: draft.at.toUtc(),
    offsetMinutes: draft.offsetMinutes,
    kilograms: roundKilograms(draft.kilograms),
    bodyFatPercent: draft.bodyFatPercent,
    waistCentimeters: draft.waistCentimeters,
    source: draft.source,
  );
}
