import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final currentDateProvider = Provider<LocalDate>((ref) {
  final now = ref.watch(clockProvider)();
  return LocalDate.fromInstant(now, now.timeZoneOffset);
});

DateTime localMidnight(LocalDate date, Duration utcOffset) =>
    DateTime.utc(date.year, date.month, date.day).subtract(utcOffset);
