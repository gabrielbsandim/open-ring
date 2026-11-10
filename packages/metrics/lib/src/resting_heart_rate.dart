typedef BpmSample = ({DateTime at, int bpm});

double? restingHeartRate(
  Iterable<BpmSample> samples, {
  Duration window = const Duration(minutes: 30),
  int minSamples = 3,
}) {
  if (window <= Duration.zero) {
    throw ArgumentError.value(window, 'window', 'must be positive');
  }
  if (minSamples < 1) {
    throw ArgumentError.value(minSamples, 'minSamples', 'must be at least 1');
  }
  // A zero is a slot the ring could not measure, not a reading.
  final valid = samples.where((s) => s.bpm > 0).toList()
    ..sort((a, b) => a.at.compareTo(b.at));

  double? lowest;
  var end = 0;
  var sum = 0;
  for (var start = 0; start < valid.length; start++) {
    final limit = valid[start].at.add(window);
    while (end < valid.length && valid[end].at.isBefore(limit)) {
      sum += valid[end].bpm;
      end++;
    }
    final count = end - start;
    final mean = sum / count;
    sum -= valid[start].bpm;
    if (count < minSamples) continue;
    if (lowest != null && lowest <= mean) continue;
    lowest = mean;
  }
  return lowest;
}
