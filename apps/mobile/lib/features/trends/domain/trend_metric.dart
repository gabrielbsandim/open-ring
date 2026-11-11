enum TrendMetric {
  restingHeartRate,
  hrv,
  sleepDuration,
  sleepScore,
  steps,
  spo2;

  bool get isNightly => this != TrendMetric.steps;
}

enum TrendRange {
  week(7),
  month(30),
  quarter(90);

  new(this.days);

  final int days;
}

final int trendHistoryDays = TrendRange.values
    .map((r) => r.days)
    .reduce((a, b) => a > b ? a : b);
