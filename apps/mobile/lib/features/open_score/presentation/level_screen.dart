import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/application/level_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/level_view.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';
import 'package:open_ring/features/open_score/presentation/day_tag_sheet.dart';
import 'package:open_ring/features/open_score/presentation/level_block.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class LevelKeys {
  static const forming = Key('level_forming');
  static const value = Key('level_value');
  static const change = Key('level_change');
  static const was = Key('level_was');
  static const tagged = Key('level_tagged');
  static const today = Key('level_today');
  static const todayMath = Key('level_today_math');
  static const account = Key('level_account');
  static const counted = Key('level_account_counted');
  static const more = Key('level_account_more');
  static const weights = Key('level_account_weights');

  static Key row(LocalDate date) => Key('level_row_${date.iso}');
}

const _minus = '−';

class LevelScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<LevelScreen> createState() => _LevelState();
}

class _LevelState extends ConsumerState<LevelScreen> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(
      enabledModulesProvider.select(
        (modules) => modules.value?.contains(ModuleId.openScore) ?? false,
      ),
    );
    return AppPage(
      title: l10n.levelTitle,
      subtitle: on ? l10n.levelLead : null,
      children: on ? _content(l10n) : [],
    );
  }

  List<Widget> _content(AppLocalizations l10n) {
    final history = ref.watch(dayScoreHistoryProvider);
    final track = ref.watch(levelTrackProvider);
    if (history.hasError || track.hasError) {
      return [BodyText(l10n.metricLoadError)];
    }
    final days = history.value;
    final steps = track.value;
    if (days == null || steps == null) return const [SizedBox(height: 96)];
    final level = steps.level;
    if (level == null) return _forming(l10n, steps);
    return _formed(l10n, days, steps, level);
  }

  List<Widget> _forming(AppLocalizations l10n, LevelTrack track) => [
    MetricCard(
      key: LevelKeys.forming,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(title: l10n.levelTitle, note: l10n.levelForming),
          const SizedBox(height: 12),
          Text(
            l10n.levelBuildingTitle(track.missing),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(child: LevelProgress(counted: track.counted)),
          const SizedBox(height: 10),
          BodyText(l10n.levelFormingBody(track.counted, levelSeedDays)),
          const SizedBox(height: 8),
          CaptionText(l10n.levelFormingNote),
        ],
      ),
    ),
    const SizedBox(height: cardGap),
    DayScoreListCard(
      title: l10n.levelHowTitle,
      lines: [l10n.levelHow1, l10n.levelHow2, l10n.levelHow3],
    ),
  ];

  List<Widget> _formed(
    AppLocalizations l10n,
    DayScoreHistory history,
    LevelTrack track,
    double level,
  ) {
    final format = MetricFormat.of(context);
    final tag = ref.watch(dayTagsProvider).value?[history.today];
    final score = history.scoredOn(history.today)?.value;
    return [
      _Hero(track: track, level: level, today: history.today),
      if (tag != null) ...[
        const SizedBox(height: cardGap),
        _Tagged(tag: tag, level: level),
      ],
      if (tag == null && score != null) ...[
        const SizedBox(height: cardGap),
        _Today(score: score, level: level),
      ],
      const SizedBox(height: cardGap),
      _Account(
        track: track,
        all: _all,
        onToggle: () => setState(() => _all = !_all),
        onDay: (date) => context.go(AppPaths.dayScoreOn(date.iso)),
      ),
      const SizedBox(height: cardGap),
      DayScoreListCard(
        title: l10n.levelNeverTitle,
        lines: [
          l10n.levelNever1,
          l10n.levelNever2,
          l10n.levelNever3,
          l10n.levelNever4,
        ],
      ),
      const SizedBox(height: cardGap),
      CaptionText(format.l10n.levelFoot),
    ];
  }
}

class _Head extends StatelessWidget {
  const new({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 4,
    children: [
      AccentTitle(title: title, accent: AppColors.of(context).textPrimary),
      CaptionText(note),
    ],
  );
}

class _Hero extends StatelessWidget {
  const new({required this.track, required this.level, required this.today});

  final LevelTrack track;
  final double level;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final thenDate = today.addDays(-1 - levelAccountDays);
    final then = track.on(thenDate)?.after;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(title: l10n.levelTitle, note: l10n.levelTodayLine),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      key: LevelKeys.value,
                      levelNumber(format, level),
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    CaptionText(l10n.levelMeanCaption),
                  ],
                ),
              ),
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      key: LevelKeys.change,
                      then == null
                          ? l10n.levelFirstDays
                          : l10n.levelChange28(
                              format.signed(level - then, digits: 1),
                            ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (then != null)
                      CaptionText(
                        key: LevelKeys.was,
                        l10n.levelWas(
                          levelNumber(format, then),
                          format.monthDay(thenDate),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tagged extends StatelessWidget {
  const new({required this.tag, required this.level});

  final DayTag tag;
  final double level;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    return MetricCard(
      key: LevelKeys.tagged,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(dayTagIcon(tag), color: colors.textLabel),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BodyText(
              format.l10n.levelTodayTagged(
                dayTagLabel(format.l10n, tag),
                levelNumber(format, level),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Today extends StatelessWidget {
  const new({required this.score, required this.level});

  final int score;
  final double level;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final line = levelNumber(format, level);
    final diff = levelNumber(format, (score - level).abs());
    final where = switch (levelSide(score, level)) {
      LevelSide.above => l10n.levelRelAbove(diff),
      LevelSide.on => l10n.levelRelOn,
      LevelSide.below => l10n.levelRelBelow(diff),
    };
    return MetricCard(
      key: LevelKeys.today,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.levelTodayTitle, accent: colors.textPrimary),
          const SizedBox(height: 8),
          BodyText(
            '${l10n.levelTodayScore(score, where)} '
            '${levelCloseText(format, level, score)}',
          ),
          const SizedBox(height: 8),
          _Math(
            key: LevelKeys.todayMath,
            '$line + ${levelRate(format)} × (${format.integer(score)} '
            '$_minus $line) = '
            '${levelNumber(format, levelAfter(level, score))}',
          ),
        ],
      ),
    );
  }
}

class _Math extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceInner,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Account extends StatelessWidget {
  const new({
    required this.track,
    required this.all,
    required this.onToggle,
    required this.onDay,
  });

  final LevelTrack track;
  final bool all;
  final VoidCallback onToggle;
  final ValueChanged<LocalDate> onDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final rows = levelAccount(track);
    final weights = track.weights;
    final counted = rows.where((step) => step.counted).toList();
    final tagged = rows.where((step) => step.day.excluded).length;
    final blank = rows.length - counted.length - tagged;
    final out = [
      if (tagged > 0) l10n.levelLeftTagged(tagged),
      if (blank > 0) l10n.levelLeftBlank(blank),
    ];
    final weighted = [for (final step in rows) ?weights[step.date]];
    final share = weighted.fold<double>(0, (sum, weight) => sum + weight);
    final rate = levelRate(format);
    final label = theme.textTheme.labelMedium?.copyWith(
      color: colors.textLabel,
    );
    return MetricCard(
      key: LevelKeys.account,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.levelAccountTitle,
            accent: colors.textPrimary,
          ),
          const SizedBox(height: 8),
          BodyText(l10n.levelAccountBody(rate)),
          const SizedBox(height: 8),
          _Math(l10n.levelAccountFormula(rate)),
          const SizedBox(height: 8),
          CaptionText(
            l10n.levelAccountExample(
              format.decimal(levelAlpha * 10, digits: 2),
              levelSeedDays,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.levelLast28,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          BodyText(
            key: LevelKeys.counted,
            [
              l10n.levelCounted(counted.length, rows.length),
              if (out.isNotEmpty) l10n.levelLeftOut(out.join(', ')),
            ].join(' '),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Row(
              children: [
                Expanded(flex: 4, child: Text(l10n.levelColDay, style: label)),
                Expanded(
                  flex: 2,
                  child: Text(
                    l10n.levelColScore,
                    style: label,
                    textAlign: TextAlign.end,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    l10n.levelColEffect,
                    style: label,
                    textAlign: TextAlign.end,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    l10n.levelColWeight,
                    style: label,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
          for (final step in rows.take(all ? rows.length : levelAccountShort))
            _Row(
              key: LevelKeys.row(step.date),
              step: step,
              weight: weights[step.date],
              onTap: () => onDay(step.date),
            ),
          const SizedBox(height: 10),
          if (rows.length > levelAccountShort)
            SecondaryButton(
              key: LevelKeys.more,
              label: all
                  ? l10n.levelShowWeek(levelAccountShort)
                  : l10n.levelShowAll(rows.length),
              onPressed: onToggle,
            ),
          if (weighted.isNotEmpty) ...[
            const SizedBox(height: 10),
            CaptionText(
              key: LevelKeys.weights,
              l10n.levelWeightNote(
                weighted.length,
                format.percent(share * 100),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const new({
    required this.step,
    required this.weight,
    required this.onTap,
    super.key,
  });

  final LevelStep step;
  final double? weight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final day = format.monthDay(step.date);
    final tag = ref.watch(dayTagsProvider).value?[step.date];
    final effect = step.effect;
    final weight = this.weight;
    final score = step.day.score;
    final counted = effect != null && weight != null && score != null;
    final reason = counted ? null : _reason(l10n, tag, score);
    final effectText = effect == null ? '' : format.signed(effect, digits: 2);
    final weightText = weight == null
        ? ''
        : l10n.metricPercent(format.decimal(weight * 100, digits: 1));
    final body = theme.textTheme.bodyMedium;
    return Semantics(
      button: true,
      label: reason == null
          ? l10n.levelRowSemantics(day, score ?? 0, effectText, weightText)
          : '$day, $reason',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  day,
                  style: body?.copyWith(
                    color: reason == null ? null : colors.textLabel,
                  ),
                ),
              ),
              if (reason != null)
                Expanded(
                  flex: 8,
                  child: Text(
                    reason,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textLabel,
                    ),
                  ),
                ),
              if (reason == null) ...[
                _Cell(
                  flex: 2,
                  text: format.integer(score ?? 0),
                  style: body?.copyWith(fontWeight: FontWeight.w700),
                ),
                _Cell(flex: 3, text: effectText, style: body),
                _Cell(
                  flex: 3,
                  text: weightText,
                  style: body?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _reason(AppLocalizations l10n, DayTag? tag, int? score) {
    if (tag != null && score != null) {
      return l10n.levelRowTagged(dayTagLabel(l10n, tag), score);
    }
    if (tag != null) return l10n.levelRowTaggedNone(dayTagLabel(l10n, tag));
    if (score == null) return l10n.levelRowBlank;
    return l10n.levelRowSeed(score);
  }
}

class _Cell extends StatelessWidget {
  const new({required this.flex, required this.text, required this.style});

  final int flex;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: style?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}
