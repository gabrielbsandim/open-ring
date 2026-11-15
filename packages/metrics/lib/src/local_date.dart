final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

extension type const LocalDate._(({int year, int month, int day}) _ymd) {
  const new(int year, int month, int day)
    : this._((year: year, month: month, day: day));

  factory fromInstant(DateTime instant, Duration utcOffset) {
    final wall = instant.toUtc().add(utcOffset);
    return LocalDate(wall.year, wall.month, wall.day);
  }

  // Null for anything that is not a real calendar date written as YYYY-MM-DD.
  static LocalDate? tryParse(String? iso) {
    final match = _isoDate.firstMatch(iso ?? '');
    if (match == null) return null;
    final date = LocalDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    return date.addDays(0).iso == iso ? date : null;
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
