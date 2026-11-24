import 'package:flutter/material.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/domain/ai_cost.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_reading.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_usage_summary.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiSheetKeys {
  static const confidence = Key('ai_sheet_confidence');
  static const dropped = Key('ai_sheet_dropped');
  static const usage = Key('ai_sheet_usage');
  static const usage30 = Key('ai_sheet_usage30');
  static const cost = Key('ai_sheet_cost');
}

/// The rule of decision 7 applied at display time, so a stored card whose
/// shown level disagrees with its two inputs still shows the lower one.
AiConfidence aiShownConfidence(ValidatedAiCard card) =>
    AiConfidence.minOf(card.modelConfidence, card.coverageConfidence);

Future<void> _show(BuildContext context, Key key, List<Widget> children) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        key: key,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: children,
          ),
        ),
      ),
    );

Widget _title(BuildContext context, String text) =>
    Text(text, style: Theme.of(context).textTheme.titleLarge);

Future<void> showAiConfidenceSheet(BuildContext context, ValidatedAiCard card) {
  final l10n = AppLocalizations.of(context);
  String level(AiConfidence c) => l10n.aiConfidenceLevel(c.name);
  return _show(context, AiSheetKeys.confidence, [
    _title(context, l10n.aiConfidenceTitle),
    Text(
      level(aiShownConfidence(card)),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    MetricRow(
      label: l10n.aiConfidenceModel,
      value: level(card.modelConfidence),
    ),
    MetricRow(
      label: l10n.aiConfidenceCoverage,
      value: level(card.coverageConfidence),
    ),
    BodyText(l10n.aiConfidenceFewest(card.minEvidenceDays)),
    CaptionText(l10n.aiConfidenceRule),
  ]);
}

Future<void> showAiDroppedSheet(
  BuildContext context,
  AiReading reading,
  int count,
) {
  final l10n = AppLocalizations.of(context);
  return _show(context, AiSheetKeys.dropped, [
    _title(context, l10n.aiDroppedTitle(count)),
    BodyText(l10n.aiDroppedLead(reading.cards.length + count)),
    for (final d in reading.dropped)
      MetricCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            BodyText('“${d.title}”'),
            CaptionText(l10n.aiDroppedReason(d.reason)),
          ],
        ),
      ),
  ]);
}

String _money(MetricFormat fmt, double value) =>
    fmt.decimal(value, digits: value < 0.01 ? 4 : 2);

String aiCostLine(
  AppLocalizations l10n,
  MetricFormat fmt,
  AiCost cost,
  String host,
) => switch (cost.source) {
  AiCostSource.provider => l10n.aiUsageCostProvider(
    _money(fmt, cost.cost),
    host,
  ),
  _ => l10n.aiUsageCostEstimate(_money(fmt, cost.cost), cost.currency),
};

AiCost? _stored(AiReport r) => switch ((r.cost, r.costSource)) {
  (_, AiCostSource.none) || (null, _) => null,
  (final double c, final s) => (
    cost: c,
    currency: r.costCurrency ?? '',
    source: s,
  ),
};

Future<void> showAiUsageSheet(BuildContext context, AiReport report) {
  final l10n = AppLocalizations.of(context);
  final fmt = MetricFormat.of(context);
  final host = Uri.tryParse(report.providerHost)?.host ?? '';
  final sent = aiStoredPayload(report.payloadJson);
  final (input, output) = (report.promptTokens, report.completionTokens);
  final thinking = report.reasoningTokens;
  final cost = _stored(report);
  return _show(context, AiSheetKeys.usage, [
    _title(context, l10n.aiUsageThis),
    if (sent != null)
      CaptionText(
        l10n.aiPreviewTokens(estimateAiTokens(sent.system + sent.user)),
      ),
    if (input == null || output == null)
      BodyText(l10n.aiUsageNotReported)
    else
      BodyText(
        l10n.aiUsageTokens(
          fmt.integer(input),
          fmt.integer(output),
          thinking == null ? 'none' : fmt.integer(thinking),
        ),
      ),
    if (cost != null)
      BodyText(key: AiSheetKeys.cost, aiCostLine(l10n, fmt, cost, host)),
  ]);
}

Future<void> showAiUsage30Sheet(
  BuildContext context,
  AiUsageSummary summary, {
  required int? cap,
}) {
  final l10n = AppLocalizations.of(context);
  final fmt = MetricFormat.of(context);
  final cost = summary.cost;
  return _show(context, AiSheetKeys.usage30, [
    _title(context, l10n.aiUsage30Title(summary.readings)),
    BodyText(
      l10n.aiUsageTokens(
        fmt.integer(summary.tokensIn),
        fmt.integer(summary.tokensOut),
        'none',
      ),
    ),
    if (cost != null)
      BodyText(
        key: AiSheetKeys.cost,
        aiCostLine(l10n, fmt, cost, summary.costHost),
      ),
    MetricRow(
      label: l10n.aiAdvancedTokenCap,
      value: cap == null ? '' : fmt.integer(cap),
    ),
    if (cap == null) CaptionText(l10n.aiAdvancedTokenCapNone),
    CaptionText(l10n.aiUsage30Note),
  ]);
}
