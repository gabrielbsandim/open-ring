import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/sleep_night.dart';

const sleepRegularityEpochMinutes = 5;
const int sleepRegularityEpochsPerDay = 24 * 60 ~/ sleepRegularityEpochMinutes;
const sleepRegularityMinPairs = 14;

typedef SleepRegularity = ({double index, int pairs});

typedef _Epoch = ({LocalDate date, int slot});

Set<_Epoch> _asleepEpochs(Iterable<SleepSpan> spans) {
  const epoch = Duration(minutes: sleepRegularityEpochMinutes);
  final asleep = <_Epoch>{};
  for (final span in spans.where((s) => s.isAsleep)) {
    final start = span.start.toUtc().add(span.utcOffset);
    final end = span.end.toUtc().add(span.utcOffset);
    final floored = DateTime.utc(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute - start.minute % sleepRegularityEpochMinutes,
    );
    var at = floored.isBefore(start) ? floored.add(epoch) : floored;
    while (at.isBefore(end)) {
      asleep.add((
        date: LocalDate(at.year, at.month, at.day),
        slot: (at.hour * 60 + at.minute) ~/ sleepRegularityEpochMinutes,
      ));
      at = at.add(epoch);
    }
  }
  return asleep;
}

/// The Sleep Regularity Index over the pairs of consecutive days in [days]:
/// 100 when every day repeats the one before, 0 at chance, -100 when opposite.
SleepRegularity? sleepRegularity(
  Iterable<SleepSpan> spans, {
  required Set<LocalDate> days,
}) {
  final firsts = [
    for (final day in days)
      if (days.contains(day.addDays(1))) day,
  ];
  if (firsts.length < sleepRegularityMinPairs) return null;
  final asleep = _asleepEpochs(spans);
  var same = 0;
  for (final day in firsts) {
    same += _sameEpochs(asleep, day);
  }
  final total = firsts.length * sleepRegularityEpochsPerDay;
  return (index: -100 + 200 * same / total, pairs: firsts.length);
}

/// One index per pair of consecutive days in [days], dated by the second day,
/// so a trend reads pairs that never overlap.
List<DailyValue> dailySleepRegularity(
  Iterable<SleepSpan> spans, {
  required Set<LocalDate> days,
}) {
  final asleep = _asleepEpochs(spans);
  final seconds = [
    for (final day in days)
      if (days.contains(day.addDays(-1))) day,
  ]..sort((a, b) => a.compareTo(b));
  return [
    for (final day in seconds)
      (
        date: day,
        value:
            -100 +
            200 *
                _sameEpochs(asleep, day.addDays(-1)) /
                sleepRegularityEpochsPerDay,
      ),
  ];
}

int _sameEpochs(Set<_Epoch> asleep, LocalDate day) {
  final next = day.addDays(1);
  var same = 0;
  for (var slot = 0; slot < sleepRegularityEpochsPerDay; slot++) {
    final now = asleep.contains((date: day, slot: slot));
    final later = asleep.contains((date: next, slot: slot));
    if (now == later) same++;
  }
  return same;
}
