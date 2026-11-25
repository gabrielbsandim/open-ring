import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/domain/ai_cost.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_report_validator.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/health_context_v2.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';

abstract final class AiFormulaKeys {
  static const intro = Key('ai_formula_intro');
  static const summary = Key('ai_formula_summary');
  static const facts = Key('ai_formula_facts');
  static const check = Key('ai_formula_check');
  static const confidence = Key('ai_formula_confidence');
  static const tokens = Key('ai_formula_tokens');
  static const ours = Key('ai_formula_ours');
  static const unchecked = Key('ai_formula_unchecked');
  static const estimate = Key('ai_formula_estimate');
}

@immutable
class AiFormulaNumbers {
  const new({
    this.window = AiContextWindow.standard,
    this.longWindow = AiContextWindow.extended,
    this.minFactDays = aiMinFactDays,
    this.maxCited = aiMaxEvidenceIds,
    this.citablePeriods = aiCitablePeriods,
    this.coverageHighDays = aiCoverageHighDays,
    this.coverageMediumDays = aiCoverageMediumDays,
    this.bytesPerToken = aiBytesPerToken,
    this.priceTokens = aiPriceTokens,
    this.minDaysWithData = aiMinDaysWithData,
    this.maxCards = aiMaxReportCards,
  });

  final AiContextWindow window;
  final AiContextWindow longWindow;
  final int minFactDays;
  final int maxCited;
  final List<int> citablePeriods;
  final int coverageHighDays;
  final int coverageMediumDays;
  final int bytesPerToken;
  final int priceTokens;
  final int minDaysWithData;
  final int maxCards;
}

const _rules = ['cited', 'theme', 'numbers', 'action', 'words', 'links'];
const _unchecked = ['keystore', 'cleartext', 'play'];
const _ideographicLists = {'ja', 'zh'};

String _joinPeriods(Locale locale, List<int> periods) =>
    periods.join(_ideographicLists.contains(locale.languageCode) ? '、' : ', ');

class AiFormulaScreen extends StatelessWidget {
  const new({this.numbers = const AiFormulaNumbers(), super.key});

  final AiFormulaNumbers numbers;

  @override
  Widget build(BuildContext context) {
    final f = MetricFormat.of(context);
    final l = f.l10n;
    final n = numbers;
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final periods = _joinPeriods(
      Localizations.localeOf(context),
      n.citablePeriods,
    );
    final longDays = n.longWindow.maxDays;
    final longWeeks = n.longWindow.maxWeeks;
    return AppPage(
      title: l.formulaLink,
      children: [
        BodyText(l.aiFormulaIntro, key: AiFormulaKeys.intro),
        const SizedBox(height: 16),
        _card(
          AiFormulaKeys.summary,
          l.aiFormulaSummaryTitle,
          c,
          t,
          body: l.aiFormulaSummaryBody(n.window.maxDays, n.window.maxWeeks),
          rows: [
            for (final level in AiDetailLevel.values)
              _LevelRow(
                title: l.aiDetailLevel(level.name),
                text: l.aiFormulaLevel(level.name, longDays, longWeeks),
              ),
          ],
          note: l.aiFormulaNever,
        ),
        const SizedBox(height: cardGap),
        _card(
          AiFormulaKeys.facts,
          l.aiFormulaFactsTitle,
          c,
          t,
          body: l.aiFormulaFactsBody(n.minFactDays),
        ),
        const SizedBox(height: cardGap),
        _card(
          AiFormulaKeys.check,
          l.aiFormulaCheckTitle,
          c,
          t,
          rows: [
            for (var i = 0; i < _rules.length; i++)
              _NumberedRow(
                number: '${i + 1}',
                text: l.aiFormulaRule(_rules[i], periods, n.maxCited),
              ),
          ],
          note: l.aiFormulaThousands,
        ),
        const SizedBox(height: cardGap),
        _card(
          AiFormulaKeys.confidence,
          l.aiConfidenceTitle,
          c,
          t,
          expr: l.aiFormulaConfidenceExpr(
            n.coverageHighDays,
            n.coverageMediumDays,
            n.coverageHighDays - 1,
          ),
          note: l.aiConfidenceRule,
        ),
        const SizedBox(height: cardGap),
        _card(
          AiFormulaKeys.tokens,
          l.aiFormulaTokensTitle,
          c,
          t,
          expr: l.aiFormulaTokensExpr(
            n.bytesPerToken,
            f.integer(n.priceTokens),
          ),
          note: l.aiFormulaTokensNote,
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: AiFormulaKeys.ours,
          title: l.dayScoreFormulaSourceOursTitle,
          icon: Icons.edit_outlined,
          facts: [
            l.aiFormulaOurs(
              n.coverageMediumDays,
              n.coverageHighDays,
              n.bytesPerToken,
              n.minDaysWithData,
              n.maxCards,
            ),
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: AiFormulaKeys.unchecked,
          title: l.effortFormulaUncheckedTitle,
          icon: Icons.schedule,
          facts: [for (final item in _unchecked) l.aiFormulaUnchecked(item)],
        ),
        const SizedBox(height: 16),
        CaptionText(l.metricEstimateNote, key: AiFormulaKeys.estimate),
      ],
    );
  }
}

Widget _card(
  Key key,
  String title,
  AppColors c,
  TextTheme t, {
  String? body,
  List<Widget> rows = const [],
  String? expr,
  String? note,
}) => MetricCard(
  key: key,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AccentTitle(title: title, accent: c.textPrimary),
      if (body != null) ...[const SizedBox(height: 8), BodyText(body)],
      for (final row in rows) ...[const SizedBox(height: 10), row],
      if (expr != null) ...[
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceInner,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(expr, style: numberStyle(t.bodySmall)),
          ),
        ),
      ],
      if (note != null) ...[const SizedBox(height: 10), CaptionText(note)],
    ],
  ),
);

class _LevelRow extends StatelessWidget {
  const new({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 2,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      BodyText(text),
    ],
  );
}

class _NumberedRow extends StatelessWidget {
  const new({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(number, style: numberStyle(Theme.of(context).textTheme.titleSmall)),
      Expanded(child: BodyText(text)),
    ],
  );
}
