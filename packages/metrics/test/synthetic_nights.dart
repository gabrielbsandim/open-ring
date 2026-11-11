// Synthetic on purpose: every value below is invented. Recorded ring data or
// anyone's real health data must never enter this file.
import 'package:metrics/metrics.dart';

const ringNoData = 0;
const ringError = 1;
const ringLight = 2;
const ringDeep = 3;
const ringRem = 4;
const ringAwake = 5;

typedef RingPeriod = (int code, int minutes);

const Map<int, SleepPhase> _phases = {
  ringLight: SleepPhase.light,
  ringDeep: SleepPhase.deep,
  ringRem: SleepPhase.rem,
  ringAwake: SleepPhase.awake,
};

final class SyntheticZone {
  const new(this.before, {this.changeAt, Duration? after})
    : after = after ?? before;

  final Duration before;
  final DateTime? changeAt;
  final Duration after;

  Duration offsetAt(DateTime instant) {
    final change = changeAt;
    if (change == null || instant.isBefore(change)) return before;
    return after;
  }

  DateTime instantOf(LocalDate date, int minuteOfDay) {
    final wall = DateTime.utc(date.year, date.month, date.day, 0, minuteOfDay);
    return wall.subtract(offsetAt(wall.subtract(before)));
  }
}

const saoPaulo = SyntheticZone(Duration(hours: -3));

final berlinFallBack = SyntheticZone(
  const Duration(hours: 2),
  changeAt: DateTime.utc(2026, 10, 25, 1),
  after: const Duration(hours: 1),
);

final newYorkSpringForward = SyntheticZone(
  const Duration(hours: -5),
  changeAt: DateTime.utc(2026, 3, 8, 7),
  after: const Duration(hours: -4),
);

// Same conversion as ColmiDriver: start > end means the evening before, and
// codes 0 and 1 advance the clock without producing a span.
List<SleepSpan> ringSleepSpans({
  required LocalDate wake,
  required int startMinute,
  required int endMinute,
  required List<RingPeriod> periods,
  required SyntheticZone zone,
}) {
  final first = startMinute > endMinute
      ? startMinute - Duration.minutesPerDay
      : startMinute;
  var cursor = zone.instantOf(wake, first);
  final spans = <SleepSpan>[];
  for (final (code, minutes) in periods) {
    if (minutes < 0 || minutes > 255) {
      throw ArgumentError.value(minutes, 'minutes', 'the ring sends one byte');
    }
    final end = cursor.add(Duration(minutes: minutes));
    final phase = _phases[code];
    if (phase != null && minutes > 0) {
      spans.add(
        SleepSpan(
          start: cursor,
          end: end,
          phase: phase,
          utcOffset: zone.offsetAt(cursor),
        ),
      );
    }
    cursor = end;
  }
  return spans;
}

const heartRateSlot = Duration(minutes: 5);
const hrvSlot = Duration(minutes: 30);

const referenceTrough = [53, 52, 51, 50, 52, 52];
const _wobble = [0, 2, 1, 3, 1, 0, 2, 3];
const _hrvPattern = [-4, 3, 0, 5, -2, -1, 2, -3];
const _asleepBpm = 62;
const _awakeBpm = 78;

typedef BpmOverride = int? Function(DateTime at);

List<BpmSample> ringHeartRate({
  required DateTime from,
  required DateTime to,
  required DateTime sleepStart,
  required DateTime sleepEnd,
  required DateTime troughAt,
  int shift = 0,
  BpmOverride? override,
}) {
  final samples = <BpmSample>[];
  var slot = 0;
  for (var at = from; at.isBefore(to); at = at.add(heartRateSlot)) {
    final bpm =
        override?.call(at) ??
        _bpm(at, slot, sleepStart, sleepEnd, troughAt, shift);
    samples.add((at: at, bpm: bpm));
    slot++;
  }
  return samples;
}

int _bpm(
  DateTime at,
  int slot,
  DateTime sleepStart,
  DateTime sleepEnd,
  DateTime troughAt,
  int shift,
) {
  final wobble = _wobble[slot % _wobble.length];
  if (at.isBefore(sleepStart) || !at.isBefore(sleepEnd)) {
    return _awakeBpm + wobble;
  }
  final index = at.difference(troughAt).inMinutes ~/ heartRateSlot.inMinutes;
  if (at.isBefore(troughAt) || index >= referenceTrough.length) {
    return _asleepBpm + wobble + shift;
  }
  return referenceTrough[index] + shift;
}

List<HrvReading> ringHrv({
  required DateTime from,
  required DateTime to,
  required int base,
  bool Function(DateTime at)? missing,
}) {
  final readings = <HrvReading>[];
  var slot = 0;
  for (var at = from; at.isBefore(to); at = at.add(hrvSlot)) {
    final measured = missing == null || !missing(at);
    readings.add((
      at: at,
      milliseconds: measured
          ? base + _hrvPattern[slot % _hrvPattern.length]
          : 0,
    ));
    slot++;
  }
  return readings;
}

const referencePeriods = <RingPeriod>[
  (ringAwake, 42),
  (ringLight, 40),
  (ringDeep, 30),
  (ringLight, 33),
  (ringRem, 20),
  (ringAwake, 18),
  (ringLight, 45),
  (ringDeep, 22),
  (ringRem, 25),
  (ringLight, 50),
  (ringAwake, 12),
  (ringLight, 31),
  (ringRem, 15),
  (ringLight, 85),
  (ringAwake, 12),
];

List<RingPeriod> withoutRem(List<RingPeriod> periods) => [
  for (final (code, minutes) in periods)
    (code == ringRem ? ringLight : code, minutes),
];

const referenceSpo2 = [97, 96, 95, 89, 94, 96, 97, 88];
const referenceStartMinute = 1387;
const referenceEndMinute = 427;

final class SyntheticNight {
  const new({
    required this.spans,
    required this.heartRate,
    required this.hrv,
    required this.spo2,
  });

  final List<SleepSpan> spans;
  final List<BpmSample> heartRate;
  final List<HrvReading> hrv;
  final List<Spo2Reading> spo2;

  NightReport report(
    LocalDate date, {
    List<SleepSpan> extraSpans = const [],
    bool remMeasured = true,
  }) {
    final night = mainNightByDate(stitchSleep([...spans, ...extraSpans]))[date];
    if (night == null) {
      return NightReport(
        night: null,
        sleep: sleepScore(null, remMeasured: remMeasured),
        restingHeartRate: null,
        hrv: null,
        spo2: null,
      );
    }
    return NightReport(
      night: night,
      sleep: sleepScore(night, remMeasured: remMeasured),
      restingHeartRate: restingHeartRate(
        heartRate.where((s) => during(s.at, night)),
      ),
      hrv: nightlyHrv(hrv.where((r) => during(r.at, night))),
      spo2: spo2NightSummary(spo2, from: night.start, to: night.end),
    );
  }
}

final class NightReport {
  const new({
    required this.night,
    required this.sleep,
    required this.restingHeartRate,
    required this.hrv,
    required this.spo2,
  });

  final SleepNight? night;
  final ScoreResult<SleepFactor> sleep;
  final double? restingHeartRate;
  final double? hrv;
  final Spo2NightSummary? spo2;
}

bool during(DateTime at, SleepNight night) =>
    !at.isBefore(night.start) && at.isBefore(night.end);

SyntheticNight referenceNight({
  required LocalDate wake,
  required SyntheticZone zone,
  int startMinute = referenceStartMinute,
  int endMinute = referenceEndMinute,
  List<RingPeriod> periods = referencePeriods,
  int heartRateShift = 0,
  int hrvBase = 50,
  BpmOverride? heartRateOverride,
  bool Function(DateTime at)? hrvMissing,
}) {
  final spans = ringSleepSpans(
    wake: wake,
    startMinute: startMinute,
    endMinute: endMinute,
    periods: periods,
    zone: zone,
  );
  final from = zone.instantOf(wake.addDays(-1), 18 * 60);
  final to = zone.instantOf(wake, 12 * 60);
  return SyntheticNight(
    spans: spans,
    heartRate: ringHeartRate(
      from: from,
      to: to,
      sleepStart: spans.first.start,
      sleepEnd: spans.last.end,
      troughAt: zone.instantOf(wake, 3 * 60),
      shift: heartRateShift,
      override: heartRateOverride,
    ),
    hrv: ringHrv(from: from, to: to, base: hrvBase, missing: hrvMissing),
    spo2: [
      (at: zone.instantOf(wake, -2 * 60), percent: 61),
      for (var hour = 0; hour < referenceSpo2.length; hour++)
        (at: zone.instantOf(wake, hour * 60), percent: referenceSpo2[hour]),
      (at: zone.instantOf(wake, 9 * 60), percent: 0),
    ],
  );
}
