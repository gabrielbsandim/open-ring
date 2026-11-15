import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';

import 'metrics_fakes.dart';

BaselineDeviation z(double zScore) =>
    BaselineDeviation(today: 1, baseline: 1, zScore: zScore);

DayScoreInputs day({
  int? sleepScore = 80,
  int? steps = 8000,
  double? intensityMinutes = 150,
  bool baselines = true,
  double? stressZ = -1,
  double? spo2Mean = 96,
  int? readiness,
}) => DayScoreInputs(
  sleepScore: sleepScore,
  steps: steps,
  stepGoal: 8000,
  intensityMinutes: intensityMinutes,
  hrv: baselines ? z(1) : null,
  restingHeartRate: baselines ? z(-1) : null,
  stress: stressZ == null ? null : z(stressZ),
  spo2Mean: spo2Mean,
  readiness: readiness,
);

DayScoreHistory historyOf(DayScoreInputs today, {bool scoredBefore = true}) =>
    DayScoreHistory(
      today: metricsToday,
      days: {
        if (scoredBefore) metricsToday.addDays(-1): day(),
        metricsToday: today,
      },
    );

// Forty days: today full, yesterday partial, two days ago without a night,
// three days ago a weaker full day, every older day full.
DayScoreHistory mixedHistory({int days = 40}) => DayScoreHistory(
  today: metricsToday,
  days: {
    for (var age = days - 1; age >= 0; age--)
      metricsToday.addDays(-age): switch (age) {
        1 => day(steps: 4000, stressZ: null, spo2Mean: null),
        2 => day(sleepScore: null),
        3 => day(sleepScore: 60),
        _ => day(),
      },
  },
);
