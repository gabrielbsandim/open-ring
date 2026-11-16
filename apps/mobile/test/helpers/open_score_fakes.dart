import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/celebration_store.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/open_score/domain/week_goal_store.dart';

final class SpyDayTagStore implements DayTagStore {
  new([Map<LocalDate, DayTag> initial = const {}])
    : _inner = InMemoryDayTagStore(initial);

  final InMemoryDayTagStore _inner;
  Error? clearFailure;
  Error? countFailure;
  int clearCalls = 0;

  @override
  Future<Map<LocalDate, DayTag>> all() => _inner.all();

  @override
  Future<bool> put(LocalDate date, DayTag tag, {required DateTime now}) =>
      _inner.put(date, tag, now: now);

  @override
  Future<bool> remove(LocalDate date) => _inner.remove(date);

  @override
  Future<int> count() async {
    final error = countFailure;
    if (error != null) throw error;
    return await _inner.count();
  }

  @override
  Future<int> clear() async {
    clearCalls++;
    final error = clearFailure;
    if (error != null) throw error;
    return await _inner.clear();
  }
}

final class SpyWeekGoalStore implements WeekGoalStore {
  new([this.goal]);

  int? goal;
  Error? clearFailure;
  int clearCalls = 0;

  @override
  Future<int?> read() async => goal;

  @override
  Future<void> write(int goal) async => this.goal = goal;

  @override
  Future<void> clear() async {
    clearCalls++;
    final error = clearFailure;
    if (error != null) throw error;
    goal = null;
  }
}

final class SpyCelebrationStore implements CelebrationStore {
  new([this.closed]);

  String? closed;
  Error? clearFailure;
  int clearCalls = 0;

  @override
  Future<String?> read() async => closed;

  @override
  Future<void> write(String isoDate) async => closed = isoDate;

  @override
  Future<void> clear() async {
    clearCalls++;
    final error = clearFailure;
    if (error != null) throw error;
    closed = null;
  }
}
