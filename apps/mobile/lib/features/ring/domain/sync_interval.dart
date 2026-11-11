enum SyncInterval {
  minutes15(15),
  minutes30(30),
  minutes60(60),
  minutes120(120);

  new(this.minutes);

  static const SyncInterval fallback = SyncInterval.minutes60;

  final int minutes;

  Duration get duration => Duration(minutes: minutes);

  static SyncInterval? fromMinutes(int? minutes) {
    for (final interval in values) {
      if (interval.minutes == minutes) return interval;
    }
    return null;
  }
}
