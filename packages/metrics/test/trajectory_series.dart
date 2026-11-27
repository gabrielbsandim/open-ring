import 'package:metrics/metrics.dart';

const seriesStart = LocalDate(2026, 11, 16);
const seriesToday = LocalDate(2026, 12, 10);
const skippedDays = {-30, -22, -13, -4, 5, 12, 19};

const protoRate = WeightRateReady(
  perWeek: -0.348097,
  low: -0.434510,
  high: -0.261684,
);

double wobble(int d) => (((d + 35) * 7919 + 13) % 101 / 101 - 0.5) * 0.8;

double round1(double value) => (value * 10).round() / 10;

List<DailyValue> prototypeSeries(double slope, {int upto = 24}) => [
  for (var d = -35; d <= upto; d++)
    if (!skippedDays.contains(d))
      (
        date: seriesStart.addDays(d),
        value: round1(78.4 - (d > 0 ? slope * d : 0) + wobble(d)),
      ),
];

List<DailyValue> straight(LocalDate last, int days) => [
  for (var i = 0; i < days; i++) (date: last.addDays(-i), value: 78),
];

WeightRateReady ready(WeightRate rate) => rate as WeightRateReady;
