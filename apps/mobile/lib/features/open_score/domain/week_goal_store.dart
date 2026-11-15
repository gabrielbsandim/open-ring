abstract interface class WeekGoalStore {
  Future<int?> read();

  Future<void> write(int goal);
}

final class InMemoryWeekGoalStore implements WeekGoalStore {
  new([this.goal]);

  int? goal;

  @override
  Future<int?> read() async => goal;

  @override
  Future<void> write(int goal) async => this.goal = goal;
}
