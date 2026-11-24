import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/domain/ai_reading.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_sheets.dart';
import 'package:open_ring/features/open_score/presentation/day_tag_sheet.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiReadingKeys {
  static const weekly = Key('ai_reading_weekly');
  static const daily = Key('ai_reading_daily');
  static const cancel = Key('ai_reading_cancel');
  static const dropped = Key('ai_reading_dropped');
  static const dashed = Key('ai_reading_dashed');
  static const confidence = Key('ai_reading_confidence');
  static const usage = Key('ai_reading_usage');
  static const usage30 = Key('ai_reading_usage30');
  static const sent = Key('ai_reading_sent');
  static const error = Key('ai_reading_error');

  static Key action(AiFailureAction a) => Key('ai_reading_action_${a.name}');

  static Key earlier(DateTime at) => Key('ai_reading_earlier_$at');

  static Key chip(String id) => Key('ai_reading_chip_$id');
}

/// Model text sits in a dashed box; the numbers in the chips come from the
/// stored snapshot of what was sent, never from today's data.
class AiReadingCard extends StatelessWidget {
  const new({
    required this.card,
    required this.facts,
    required this.model,
    super.key,
  });

  final ValidatedAiCard card;
  final Map<String, AiFactSnapshot> facts;
  final String model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CustomPaint(
        key: AiReadingKeys.dashed,
        painter: DashedBorderPainter(color: colors.strongBorder, radius: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Row(
                spacing: 8,
                children: [
                  AccentDot(color: aiFamilyColor(colors, card.family)),
                  Expanded(child: CaptionText(l10n.aiReadingWrittenBy(model))),
                ],
              ),
              Text(card.title, style: text.titleMedium),
              BodyText(card.insight),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in card.evidenceIds)
                    _chip(context, id, facts[id]),
                ],
              ),
              Text(l10n.aiReadingSuggestion, style: text.labelLarge),
              BodyText(card.action),
              InkWell(
                key: AiReadingKeys.confidence,
                onTap: () => unawaited(showAiConfidenceSheet(context, card)),
                child: CaptionText(
                  l10n.aiReadingConfidence(
                    aiShownConfidence(card).name,
                    card.minEvidenceDays,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _chip(BuildContext context, String id, AiFactSnapshot? fact) {
  final route = aiFactRoute(id);
  return MetricCard(
    key: AiReadingKeys.chip(id),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    onTap: route == null ? null : () => context.go(route),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CaptionText(aiFactChipLabel(AppLocalizations.of(context), id, fact)),
        if (fact != null)
          Text(
            aiFactValue(MetricFormat.of(context), fact),
            style: Theme.of(context).textTheme.titleSmall,
          ),
      ],
    ),
  );
}

/// The screen a chip opens, or null when the fact has no metric screen
/// (workout facts), in which case the chip opens nothing.
String? aiFactRoute(String id) {
  final name = RegExp(r'^f\.(\w+)\.').firstMatch(id)?.group(1);
  return switch (AiDailyMetric.values.asNameMap()[name]) {
    null => null,
    AiDailyMetric.sleepMin || AiDailyMetric.sleepScore => AppTab.sleep.path,
    AiDailyMetric.rhr ||
    AiDailyMetric.hrv ||
    AiDailyMetric.stress ||
    AiDailyMetric.spo2 => AppTab.heart.path,
    AiDailyMetric.steps || AiDailyMetric.activeKcal => AppTab.activity.path,
    AiDailyMetric.load => AppPaths.effort,
    AiDailyMetric.readiness => AppPaths.readiness,
    AiDailyMetric.dayScore => AppPaths.dayScore,
    AiDailyMetric.weight => AppPaths.body,
  };
}

String aiFactChipLabel(AppLocalizations l10n, String id, AiFactSnapshot? fact) {
  if (fact == null) return id;
  final match = RegExp(r'^f\.(\w+)\.(last|avg)$').firstMatch(id);
  final metric = AiDailyMetric.values.asNameMap()[match?.group(1)];
  if (match == null || metric == null) return fact.label;
  return l10n.aiFactLabel(match.group(2)!, _nameOf(l10n, metric), fact.days);
}

String aiFactValue(MetricFormat fmt, AiFactSnapshot fact) =>
    switch (fact.unit) {
      'min' => fmt.duration(Duration(minutes: fact.value.round())),
      'bpm' => fmt.bpm(fact.value),
      'ms' => fmt.ms(fact.value),
      'pct' => fmt.percent(fact.value),
      'score' || 'steps' => fmt.integer(fact.value),
      _ => '${fmt.points(fact.value)} ${fact.unit}',
    };

Color aiFamilyColor(AppColors colors, AiMetricFamily family) =>
    switch (family) {
      AiMetricFamily.sleep => colors.sleep,
      AiMetricFamily.heart => colors.heart,
      AiMetricFamily.activity => colors.activity,
      AiMetricFamily.oxygen => colors.oxygen,
      AiMetricFamily.stress => colors.stress,
      AiMetricFamily.body || AiMetricFamily.overall => colors.textLabel,
    };

String _nameOf(AppLocalizations l10n, AiDailyMetric metric) => switch (metric) {
  AiDailyMetric.sleepMin => l10n.trendsMetricSleep,
  AiDailyMetric.sleepScore => l10n.trendsMetricSleepScore,
  AiDailyMetric.rhr => l10n.trendsMetricRestingHeartRate,
  AiDailyMetric.hrv => l10n.trendsMetricHrv,
  AiDailyMetric.stress => l10n.heartMetricStress,
  AiDailyMetric.spo2 => l10n.trendsMetricSpo2,
  AiDailyMetric.steps => l10n.trendsMetricSteps,
  AiDailyMetric.activeKcal => l10n.activityActiveEnergy,
  AiDailyMetric.load => l10n.effortLoadTitle,
  AiDailyMetric.readiness => l10n.readinessTitle,
  AiDailyMetric.dayScore => l10n.dayScoreTitle,
  AiDailyMetric.weight => l10n.profileWeight,
};
