import 'package:metrics/metrics.dart';

enum DayTag {
  sick,
  travel,
  rest;

  static DayTag? tryParse(String? name) => values.asNameMap()[name];
}

const dayTagEditableDays = 7;

bool canEditDayTag(LocalDate date, {required LocalDate today}) {
  final age = today.daysSince(date);
  return age >= 0 && age < dayTagEditableDays;
}
