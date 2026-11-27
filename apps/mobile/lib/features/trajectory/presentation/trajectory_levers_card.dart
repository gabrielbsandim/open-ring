import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/trajectory/application/levers_providers.dart';
import 'package:open_ring/features/trajectory/domain/levers_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_evidence_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class TrajectoryLeversKeys {
  static const card = Key('trajectory_levers');

  static Key row(RingLever lever) => Key('trajectory_lever_${lever.name}');
}

class TrajectoryLeversCard extends ConsumerWidget {
  const new({required this.format, super.key});

  final MetricFormat format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levers = ref.watch(leversProvider).value;
    if (levers is! LeversReady) return const SizedBox.shrink();
    final l10n = format.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MetricCard(
        key: TrajectoryLeversKeys.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.trajectoryLeversTitle(
                  format.integer(leverTrendWindowDays),
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final lever in RingLever.values)
              if (levers.levers[lever] case final reading?)
                _Row(lever: lever, reading: reading, format: format),
            const SizedBox(height: 12),
            CaptionText(l10n.trajectoryLeversCaption),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const new({required this.lever, required this.reading, required this.format});

  final RingLever lever;
  final LeverReading reading;
  final MetricFormat format;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final trend = reading.trend;
    final (value, detail) = trend == null
        ? (l10n.trajectoryLeversNotYet, leverNotYet(format, reading.validDays))
        : (
            _direction(l10n, trend.direction(lever)),
            l10n.trajectoryLeverChange(
              leverAmount(format, lever, trend.change, signed: true),
              format.integer(leverTrendWindowDays),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: EvidenceTap(
        key: TrajectoryLeversKeys.row(lever),
        onTap: () => unawaited(
          showGoalEvidence(
            context,
            copy: leverEvidenceCopy(format, lever),
            yours: leverEvidenceYours(format, lever, reading),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              leverName(l10n, lever),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (trend != null)
              CaptionText(
                l10n.trajectoryLeverTypical(
                  leverTypical(format, lever, trend.typical),
                ),
              ),
            const SizedBox(height: 2),
            Text(
              value,
              style: numberStyle(Theme.of(context).textTheme.titleMedium),
            ),
            CaptionText(detail),
          ],
        ),
      ),
    );
  }
}

String _direction(AppLocalizations l10n, LeverDirection direction) =>
    switch (direction) {
      LeverDirection.rising => l10n.trajectoryLeversRising,
      LeverDirection.falling => l10n.trajectoryLeversFalling,
      LeverDirection.stable => l10n.trajectoryLeversStable,
    };

String leverName(AppLocalizations l10n, RingLever lever) => switch (lever) {
  RingLever.steps => l10n.trendsMetricSteps,
  RingLever.sleepRegularity => l10n.overallFactorSleepRegularity,
  RingLever.restingHeartRate => l10n.trendsMetricRestingHeartRate,
  RingLever.sleepDuration => l10n.trajectoryLeverDuration,
};

String leverNotYet(MetricFormat format, int validDays) =>
    format.l10n.trajectoryLeversNotYetWhy(
      format.integer(validDays),
      format.integer(leverTrendWindowDays),
      format.integer(leverTrendMinValidDays),
    );

// Steps read to the nearest hundred; a ring count is not finer than that.
double _rounded(RingLever lever, double value) => lever == RingLever.steps
    ? (value / 100).roundToDouble() * 100
    : value.roundToDouble();

/// A bare amount of [lever] (a change, an interval end), signed when asked.
String leverAmount(
  MetricFormat format,
  RingLever lever,
  double value, {
  bool signed = false,
}) {
  final rounded = _rounded(lever, value);
  final number = signed ? format.signed(rounded) : format.integer(rounded);
  return switch (lever) {
    RingLever.steps || RingLever.sleepRegularity => number,
    RingLever.restingHeartRate => format.l10n.metricBpm(number),
    RingLever.sleepDuration => format.l10n.trajectoryLeverMinutes(number),
  };
}

// An interval end that rounds to zero would hide the side it is on.
String _end(MetricFormat format, RingLever lever, double value) {
  if (_rounded(lever, value) != 0 || value == 0) {
    return leverAmount(format, lever, value, signed: true);
  }
  final digits = lever == RingLever.steps ? 0 : 1;
  final number = format.signed(value, digits: digits);
  return switch (lever) {
    RingLever.steps || RingLever.sleepRegularity => number,
    RingLever.restingHeartRate => format.l10n.metricBpm(number),
    RingLever.sleepDuration => format.l10n.trajectoryLeverMinutes(number),
  };
}

String leverTypical(MetricFormat format, RingLever lever, double value) {
  final l10n = format.l10n;
  final rounded = _rounded(lever, value);
  return switch (lever) {
    RingLever.steps => l10n.trendsStepsPerDay(format.integer(rounded)),
    RingLever.sleepRegularity => l10n.trajectoryLeverIndex(
      format.integer(rounded),
    ),
    RingLever.restingHeartRate => format.bpm(rounded),
    RingLever.sleepDuration => l10n.trendsPerNight(
      format.duration(Duration(minutes: rounded.round())),
    ),
  };
}

String leverMinimum(MetricFormat format, RingLever lever) {
  final l10n = format.l10n;
  final amount = lever.minimumChange.round();
  return switch (lever) {
    RingLever.steps => l10n.trendsStepsValue(format.integer(amount)),
    RingLever.sleepRegularity => l10n.trendsPoints(amount),
    RingLever.restingHeartRate => l10n.metricBpm(format.integer(amount)),
    RingLever.sleepDuration => l10n.trajectoryLeverMinutes(
      format.integer(amount),
    ),
  };
}

GoalEvidenceCopy leverEvidenceCopy(MetricFormat format, RingLever lever) {
  final l10n = format.l10n;
  final days = format.integer(leverTrendWindowDays);
  final minimum = leverMinimum(format, lever);
  return (
    title: leverName(l10n, lever),
    what: l10n.trajectorySheetLeverWhat(days),
    rule: l10n.trajectorySheetLeverRule(days, minimum),
    source: switch (lever) {
      RingLever.steps => l10n.trajectorySheetLeverStepsSource,
      RingLever.sleepRegularity => l10n.trajectorySheetLeverRegularitySource,
      RingLever.restingHeartRate => l10n.trajectorySheetLeverRestingSource,
      RingLever.sleepDuration => l10n.trajectorySheetLeverDurationSource,
    },
    ours: l10n.trajectorySheetLeverOurs(
      minimum,
      format.integer(leverTrendMinValidDays),
      days,
    ),
    limits: switch (lever) {
      RingLever.steps => l10n.trajectorySheetLeverStepsLimits,
      RingLever.sleepRegularity => l10n.trajectorySheetLeverRegularityLimits,
      RingLever.restingHeartRate => l10n.trajectorySheetLeverRestingLimits,
      RingLever.sleepDuration => l10n.trajectorySheetLeverDurationLimits,
    },
  );
}

/// The reader's own numbers for the sheet of [lever].
String leverEvidenceYours(
  MetricFormat format,
  RingLever lever,
  LeverReading reading,
) {
  final trend = reading.trend;
  if (trend == null) return leverNotYet(format, reading.validDays);
  final l10n = format.l10n;
  final days = format.integer(leverTrendWindowDays);
  final text = l10n.trajectorySheetLeverYours(
    leverTypical(format, lever, trend.typical),
    format.integer(trend.validDays),
    days,
    leverAmount(format, lever, trend.change, signed: true),
    _end(format, lever, trend.changeLow),
    _end(format, lever, trend.changeHigh),
  );
  return '$text ${_why(format, lever, trend)}';
}

String _why(MetricFormat format, RingLever lever, LeverTrend trend) {
  final l10n = format.l10n;
  final fan = trend.fan(lever);
  final moving = trend.direction(lever) != LeverDirection.stable;
  if (moving && fan != null) {
    return l10n.trajectorySheetLeverFan(
      format.integer(leverTrendWindowDays),
      leverAmount(format, lever, fan.low),
      leverAmount(format, lever, fan.high),
    );
  }
  if (moving) return l10n.trajectorySheetLeverMoving;
  if (trend.slopeLow > 0 || trend.slopeHigh < 0) {
    return l10n.trajectorySheetLeverSmall(leverMinimum(format, lever));
  }
  return l10n.trajectorySheetLeverZero;
}
