import 'package:metrics/src/resting_heart_rate.dart';

const zoneLowerFractions = [0.5, 0.6, 0.7, 0.8, 0.9];
const liveSampleMaxHold = Duration(seconds: 10);

int maxHeartRateForAge(int age) {
  if (age < 1 || age > 119) {
    throw ArgumentError.value(age, 'age', 'must be in 1..119');
  }
  return 220 - age;
}

final class HeartRateZone {
  const new({
    required this.number,
    required this.lowerBpm,
    required this.upperBpm,
  });

  final int number;
  final int lowerBpm;
  final int? upperBpm;

  bool contains(int bpm) {
    if (bpm < lowerBpm) return false;
    final upper = upperBpm;
    return upper == null || bpm < upper;
  }
}

final class HeartRateZones {
  factory({int? age, int? maxHeartRate}) {
    final max = maxHeartRate ?? (age == null ? null : maxHeartRateForAge(age));
    if (max == null) {
      throw ArgumentError('Pass an age or a maxHeartRate');
    }
    if (max < 100 || max > 250) {
      throw ArgumentError.value(max, 'maxHeartRate', 'must be in 100..250');
    }
    final lowers = [for (final f in zoneLowerFractions) (max * f).round()];
    return HeartRateZones._(max, [
      for (var i = 0; i < lowers.length; i++)
        HeartRateZone(
          number: i + 1,
          lowerBpm: lowers[i],
          upperBpm: i + 1 < lowers.length ? lowers[i + 1] : null,
        ),
    ]);
  }

  new _(this.maxHeartRate, List<HeartRateZone> zones)
    : zones = List.unmodifiable(zones);

  final int maxHeartRate;
  final List<HeartRateZone> zones;

  int? zoneOf(int bpm) {
    for (final z in zones.reversed) {
      if (z.contains(bpm)) return z.number;
    }
    return null;
  }

  Map<int, Duration> timeInZones(
    Iterable<BpmSample> samples, {
    Duration maxHold = liveSampleMaxHold,
  }) {
    final valid = samples.where((s) => s.bpm > 0).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final totals = {for (final z in zones) z.number: Duration.zero};
    for (var i = 0; i + 1 < valid.length; i++) {
      final zone = zoneOf(valid[i].bpm);
      if (zone == null) continue;
      final gap = valid[i + 1].at.difference(valid[i].at);
      totals[zone] = totals[zone]! + (gap < maxHold ? gap : maxHold);
    }
    return totals;
  }
}
