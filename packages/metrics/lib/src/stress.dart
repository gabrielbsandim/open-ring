typedef StressReading = ({DateTime at, int level});

enum StressBand { rest, low, medium, high }

const stressSlot = Duration(minutes: 30);
const stressMinReadings = 3;

StressBand stressBandOf(int level) => switch (level) {
  <= 25 => StressBand.rest,
  <= 50 => StressBand.low,
  <= 75 => StressBand.medium,
  _ => StressBand.high,
};

final class StressDaySummary {
  new({
    required this.mean,
    required this.min,
    required this.max,
    required this.readings,
    required Map<StressBand, Duration> timeInBand,
  }) : timeInBand = Map.unmodifiable(timeInBand);

  final double mean;
  final int min;
  final int max;
  final int readings;
  final Map<StressBand, Duration> timeInBand;

  Duration get measured =>
      timeInBand.values.fold(Duration.zero, (a, b) => a + b);
}

StressDaySummary? stressDaySummary(
  Iterable<StressReading> readings, {
  Duration slot = stressSlot,
  int minReadings = stressMinReadings,
}) {
  if (slot <= Duration.zero) {
    throw ArgumentError.value(slot, 'slot', 'must be positive');
  }
  if (minReadings < 1) {
    throw ArgumentError.value(minReadings, 'minReadings', 'must be at least 1');
  }
  final levels = [
    for (final r in readings)
      if (r.level >= 1 && r.level <= 100) r.level,
  ];
  if (levels.length < minReadings) return null;
  final timeInBand = {for (final b in StressBand.values) b: Duration.zero};
  for (final level in levels) {
    final band = stressBandOf(level);
    timeInBand[band] = timeInBand[band]! + slot;
  }
  return StressDaySummary(
    mean: levels.reduce((a, b) => a + b) / levels.length,
    min: levels.reduce((a, b) => a < b ? a : b),
    max: levels.reduce((a, b) => a > b ? a : b),
    readings: levels.length,
    timeInBand: timeInBand,
  );
}
