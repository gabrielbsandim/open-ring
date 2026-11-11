import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/heart/presentation/baseline_text.dart';
import 'package:open_ring/features/heart/presentation/heart_labels.dart';

class HeartInsight extends StatelessWidget {
  const new({required this.view, required this.metric, super.key});

  final HeartDayView view;
  final HeartMetric metric;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final (title, body, source) = switch (metric) {
      HeartMetric.heartRate => _resting(format),
      HeartMetric.hrv => _hrv(format),
      HeartMetric.spo2 => _spo2(format),
      HeartMetric.stress => (
        l10n.heartStressDayTitle,
        _stressBody(format),
        l10n.heartStressSource,
      ),
    };
    final bands = view.stressSummary?.timeInBand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        BodyText(body),
        if (metric == HeartMetric.stress && bands != null) ...[
          const SizedBox(height: 8),
          for (final band in StressBand.values)
            MetricRow(
              label: band.label(l10n),
              value: format.duration(bands[band] ?? Duration.zero),
            ),
        ],
        const SizedBox(height: 8),
        CaptionText(source),
      ],
    );
  }

  (String, String, String) _resting(MetricFormat format) {
    final input = view.baselines.restingHeartRate;
    final today = input.today;
    final l10n = format.l10n;
    return (
      today == null
          ? l10n.heartRestingTitleEmpty
          : l10n.heartRestingTitle(format.bpm(today)),
      baselineLine(
        format,
        input,
        compared: (d) => restingVersusBaseline(format, d),
        missing: l10n.heartRestingMissing,
      ),
      l10n.heartRestingSource,
    );
  }

  (String, String, String) _hrv(MetricFormat format) {
    final input = view.baselines.hrv;
    final today = input.today;
    final l10n = format.l10n;
    return (
      today == null
          ? l10n.heartHrvTitleEmpty
          : l10n.heartHrvTitle(format.ms(today)),
      baselineLine(
        format,
        input,
        compared: (d) => hrvVersusBaseline(format, d),
        missing: l10n.heartHrvMissing,
      ),
      l10n.heartHrvSource,
    );
  }

  (String, String, String) _spo2(MetricFormat format) {
    final summary = view.spo2Night;
    final l10n = format.l10n;
    final body = summary == null
        ? l10n.heartSpo2Missing
        : '${l10n.heartSpo2Summary(format.percent(summary.mean), format.percent(summary.min.toDouble()))} '
              '${l10n.heartSpo2Below(summary.readingsBelow)}';
    return (l10n.heartSpo2NightTitle, body, l10n.heartSpo2Source);
  }

  String _stressBody(MetricFormat format) {
    final summary = view.stressSummary;
    if (summary == null) return format.l10n.heartStressMissing;
    return format.l10n.heartStressSummary(
      format.integer(summary.mean),
      summary.min,
      summary.max,
    );
  }
}
