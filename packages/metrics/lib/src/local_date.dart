extension type const LocalDate._(({int year, int month, int day}) _ymd) {
  const new(int year, int month, int day)
    : this._((year: year, month: month, day: day));

  factory fromInstant(DateTime instant, Duration utcOffset) {
    final wall = instant.toUtc().add(utcOffset);
    return LocalDate(wall.year, wall.month, wall.day);
  }

  int get year => _ymd.year;
  int get month => _ymd.month;
  int get day => _ymd.day;

  DateTime get _utcMidnight => DateTime.utc(year, month, day);

  LocalDate addDays(int days) {
    final moved = DateTime.utc(year, month, day + days);
    return LocalDate(moved.year, moved.month, moved.day);
  }

  int daysSince(LocalDate other) =>
      _utcMidnight.difference(other._utcMidnight).inDays;

  int compareTo(LocalDate other) => _utcMidnight.compareTo(other._utcMidnight);

  String get iso {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }
}
