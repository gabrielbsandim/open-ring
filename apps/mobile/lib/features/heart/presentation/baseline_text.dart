import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';

String baselineLine(
  MetricFormat format,
  BaselineInput input, {
  required String Function(BaselineDeviation deviation) compared,
  required String missing,
}) {
  final deviation = input.deviation;
  if (deviation != null) return compared(deviation);
  if (input.today == null) return missing;
  return switch (input.baseline) {
    BaselineBuilding(:final daysCollected, :final daysNeeded) =>
      format.l10n.metricBaselineBuilding(daysCollected, daysNeeded),
    BaselineReady() => missing,
  };
}

String restingVersusBaseline(MetricFormat format, BaselineDeviation d) => format
    .l10n
    .heartRestingVsBaseline(format.signed(d.delta), format.bpm(d.baseline));

String hrvVersusBaseline(MetricFormat format, BaselineDeviation d) => format
    .l10n
    .heartHrvVsBaseline(format.signed(d.percent), format.ms(d.baseline));
