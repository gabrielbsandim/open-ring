import 'package:flutter/material.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/domain/ai_reading.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_report_validator.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiRawKeys {
  static const sheet = Key('ai_raw_sheet');
  static const text = Key('ai_raw_text');
}

/// Numbers in [raw] that match none of the facts sent with [report].
List<AiUnverifiedSpan> aiRawUnverifiedSpans(
  AiReport report,
  String raw, {
  required String replyLanguage,
}) => AiReportValidator.findUnverifiedSpans(
  raw,
  // The span check reads only the id and the value of each fact.
  facts: [
    for (final MapEntry(:key, :value) in AiReading.fromReport(
      report,
    ).facts.entries)
      HealthFact(
        id: key,
        label: value.label,
        value: value.value,
        unit: AiFactUnit.score,
        family: AiMetricFamily.overall,
        days: value.days,
      ),
  ],
  replyLanguage: replyLanguage,
);

/// Plain text only: a Text never follows links or renders markdown.
Future<void> showAiRawTextSheet(
  BuildContext context,
  AiReport report, {
  required String replyLanguage,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final raw = report.rawText ?? '';
  final spans = aiRawUnverifiedSpans(report, raw, replyLanguage: replyLanguage);
  const dotted = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
  );
  final pieces = <InlineSpan>[];
  var at = 0;
  for (final s in spans) {
    pieces
      ..add(TextSpan(text: raw.substring(at, s.start)))
      ..add(TextSpan(text: raw.substring(s.start, s.end), style: dotted))
      ..add(
        const TextSpan(
          text: '?',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
    at = s.end;
  }
  pieces.add(TextSpan(text: raw.substring(at)));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      key: AiRawKeys.sheet,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(l10n.aiRawTitle, style: theme.textTheme.titleLarge),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.error,
                ),
                Expanded(child: BodyText(l10n.aiRawBanner(report.model))),
              ],
            ),
            Text.rich(
              TextSpan(children: pieces),
              key: AiRawKeys.text,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
