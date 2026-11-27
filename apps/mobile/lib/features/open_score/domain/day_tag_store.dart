import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';

abstract interface class DayTagStore {
  Future<Map<LocalDate, DayTag>> all();

  /// False when the date already holds this tag and nothing was written.
  Future<bool> put(LocalDate date, DayTag tag, {required DateTime now});

  Future<bool> remove(LocalDate date);

  /// Every stored row, also one whose tag or date no longer parses.
  Future<int> count();

  /// Removes every row and returns how many there were.
  Future<int> clear();
}

final class InMemoryDayTagStore implements DayTagStore {
  new([Map<LocalDate, DayTag> initial = const {}]) : _tags = {...initial};

  final Map<LocalDate, DayTag> _tags;

  @override
  Future<Map<LocalDate, DayTag>> all() async => {..._tags};

  @override
  Future<bool> put(LocalDate date, DayTag tag, {required DateTime now}) async {
    if (_tags[date] == tag) return false;
    _tags[date] = tag;
    return true;
  }

  @override
  Future<bool> remove(LocalDate date) async => _tags.remove(date) != null;

  @override
  Future<int> count() async => _tags.length;

  @override
  Future<int> clear() async {
    final removed = _tags.length;
    _tags.clear();
    return removed;
  }
}
