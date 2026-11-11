typedef Spo2Reading = ({DateTime at, int percent});

const spo2LowThreshold = 90;
const spo2MinPlausible = 70;
const spo2SampleInterval = Duration(hours: 1);
const spo2MinReadings = 3;

final class Spo2NightSummary {
  const new({
    required this.min,
    required this.mean,
    required this.readings,
    required this.readingsBelow,
    required this.sampleInterval,
  });

  final int min;
  final double mean;
  final int readings;
  final int readingsBelow;
  final Duration sampleInterval;

  Duration get timeBelow => sampleInterval * readingsBelow;

  double get shareBelow => readingsBelow / readings;
}

Spo2NightSummary? spo2NightSummary(
  Iterable<Spo2Reading> readings, {
  required DateTime from,
  required DateTime to,
  Duration sampleInterval = spo2SampleInterval,
  int minReadings = spo2MinReadings,
}) {
  if (!to.isAfter(from)) {
    throw ArgumentError.value(to, 'to', 'must be after from');
  }
  if (sampleInterval <= Duration.zero) {
    throw ArgumentError.value(
      sampleInterval,
      'sampleInterval',
      'must be positive',
    );
  }
  if (minReadings < 1) {
    throw ArgumentError.value(minReadings, 'minReadings', 'must be at least 1');
  }
  final values = [
    for (final r in readings)
      if (!r.at.isBefore(from) &&
          r.at.isBefore(to) &&
          r.percent >= spo2MinPlausible &&
          r.percent <= 100)
        r.percent,
  ];
  if (values.length < minReadings) return null;
  return Spo2NightSummary(
    min: values.reduce((a, b) => a < b ? a : b),
    mean: values.reduce((a, b) => a + b) / values.length,
    readings: values.length,
    readingsBelow: values.where((v) => v < spo2LowThreshold).length,
    sampleInterval: sampleInterval,
  );
}
