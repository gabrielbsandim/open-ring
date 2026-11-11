import 'package:metrics/src/sleep_night.dart';

const remAbsentAfterNights = 7;

enum RemReporting {
  reported,
  absent,
  unknown;

  bool get measured => this != RemReporting.absent;

  static RemReporting observe({
    required int nights,
    required int nightsWithRem,
    int absentAfter = remAbsentAfterNights,
  }) {
    if (nightsWithRem < 0 || nightsWithRem > nights) {
      throw ArgumentError.value(
        nightsWithRem,
        'nightsWithRem',
        'must be between 0 and nights',
      );
    }
    if (absentAfter < 1) {
      throw ArgumentError.value(absentAfter, 'absentAfter', 'must be positive');
    }
    if (nightsWithRem > 0) return RemReporting.reported;
    if (nights >= absentAfter) return RemReporting.absent;
    return RemReporting.unknown;
  }

  static RemReporting ofNights(
    Iterable<SleepNight> nights, {
    int absentAfter = remAbsentAfterNights,
  }) => observe(
    nights: nights.length,
    nightsWithRem: nights
        .where((night) => night.timeIn(SleepPhase.rem) > Duration.zero)
        .length,
    absentAfter: absentAfter,
  );
}
