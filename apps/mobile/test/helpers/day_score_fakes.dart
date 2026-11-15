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
}) => DayScoreInputs(
  sleepScore: sleepScore,
  steps: steps,
  stepGoal: 8000,
  intensityMinutes: intensityMinutes,
  hrv: baselines ? z(1) : null,
  restingHeartRate: baselines ? z(-1) : null,
  stress: stressZ == null ? null : z(stressZ),
  spo2Mean: spo2Mean,
);

DayScoreHistory historyOf(DayScoreInputs today, {bool scoredBefore = true}) =>
    DayScoreHistory(
      today: metricsToday,
      days: {
        if (scoredBefore) metricsToday.addDays(-1): day(),
        metricsToday: today,
      },
    );
