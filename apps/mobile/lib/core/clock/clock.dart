import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final currentDateProvider = Provider<LocalDate>((ref) {
  final now = ref.watch(clockProvider)();
  return LocalDate.fromInstant(now, now.timeZoneOffset);
});

// The timer lives here and not in currentDateProvider, so a screen that only
// reads the date never holds one.
final dayRollProvider = Provider<DayRoll>((ref) {
  final dayRoll = DayRoll(
    clock: () => ref.read(clockProvider)(),
    current: () => ref.read(currentDateProvider),
    roll: () => ref.invalidate(currentDateProvider),
  );
  Timer? timer;
  void arm() {
    timer = Timer(dayRoll.untilNextDay(), () {
      dayRoll.check();
      arm();
    });
  }

  arm();
  final listener = AppLifecycleListener(onResume: dayRoll.check);
  ref.onDispose(() {
    timer?.cancel();
    listener.dispose();
  });
  return dayRoll;
});

/// Moves the current date on when the local day has changed.
final class DayRoll {
  new({required this.clock, required this.current, required this.roll});

  final DateTime Function() clock;
  final LocalDate Function() current;
  final void Function() roll;

  /// Whether the day changed since the date was read; rolls it when it did.
  bool check() {
    final now = clock();
    if (LocalDate.fromInstant(now, now.timeZoneOffset) == current()) {
      return false;
    }
    roll();
    return true;
  }

  Duration untilNextDay() {
    final now = clock();
    final next = now.isUtc
        ? DateTime.utc(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day + 1);
    return next.difference(now);
  }
}

DateTime localMidnight(LocalDate date, Duration utcOffset) =>
    DateTime.utc(date.year, date.month, date.day).subtract(utcOffset);
