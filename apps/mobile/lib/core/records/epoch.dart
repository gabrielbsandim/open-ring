extension EpochMillis on DateTime {
  int get utcMs => millisecondsSinceEpoch;

  int get offsetMinutes => timeZoneOffset.inMinutes;
}

DateTime fromUtcMs(int utcMs) => DateTime.fromMillisecondsSinceEpoch(utcMs);

DateTime utcInstant(int utcMs) =>
    DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true);

Duration offsetOf(int offsetMinutes) => Duration(minutes: offsetMinutes);
