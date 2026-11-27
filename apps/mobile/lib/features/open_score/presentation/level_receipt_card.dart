import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/presentation/day_tag_sheet.dart';
import 'package:open_ring/features/open_score/presentation/level_block.dart';

abstract final class LevelReceiptKeys {
  static const card = Key('level_receipt');
  static const note = Key('level_receipt_note');
  static const line = Key('level_receipt_line');
  static const score = Key('level_receipt_score');
  static const effect = Key('level_receipt_effect');
  static const math = Key('level_receipt_math');
}

const _minus = '−';

/// What one day did to the Level, on that day's receipt.
class LevelReceiptCard extends StatelessWidget {
  const new({
    required this.track,
    required this.date,
    required this.today,
    required this.score,
    required this.tag,
    super.key,
  });

  final LevelTrack track;
  final LocalDate date;
  final LocalDate today;
  final int? score;
  final DayTag? tag;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    return MetricCard(
      key: LevelReceiptKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: format.l10n.levelTitle,
            accent: colors.textPrimary,
          ),
          const SizedBox(height: 8),
          ..._rows(format),
        ],
      ),
    );
  }

  List<Widget> _rows(MetricFormat format) {
    final l10n = format.l10n;
    final line = date == today ? track.level : track.lineOn(date);
    if (line == null) {
      return [
        BodyText(
          key: LevelReceiptKeys.note,
          track.level == null
              ? l10n.levelReceiptForming(track.counted, levelSeedDays)
              : l10n.levelReceiptNoLine,
        ),
      ];
    }
    final lineText = levelNumber(format, line);
    final head = _Row(
      key: LevelReceiptKeys.line,
      label: l10n.levelReceiptLine,
      value: lineText,
    );
    final tag = this.tag;
    if (tag != null) {
      return [
        head,
        _none(format),
        const SizedBox(height: 6),
        CaptionText(
          key: LevelReceiptKeys.note,
          l10n.levelReceiptTagged(dayTagLabel(l10n, tag)),
        ),
      ];
    }
    final score = this.score;
    if (score == null) {
      return [
        head,
        _none(format),
        const SizedBox(height: 6),
        CaptionText(key: LevelReceiptKeys.note, l10n.levelReceiptBlank),
      ];
    }
    final after = levelAfter(line, score);
    final diff = levelNumber(format, (score - line).abs());
    final where = switch (levelSide(score, line)) {
      LevelSide.above => l10n.levelRelAbove(diff),
      LevelSide.on => l10n.levelRelOn,
      LevelSide.below => l10n.levelRelBelow(diff),
    };
    final math =
        '$lineText + ${levelRate(format)} × (${format.integer(score)} '
        '$_minus $lineText) = ${levelNumber(format, after)}';
    return [
      head,
      _Row(
        key: LevelReceiptKeys.score,
        label: l10n.levelReceiptScore,
        value: format.integer(score),
        detail: where,
      ),
      _Row(
        key: LevelReceiptKeys.effect,
        label: l10n.levelReceiptEffect,
        value: format.signed(after - line, digits: 2),
      ),
      const SizedBox(height: 6),
      CaptionText(
        key: LevelReceiptKeys.math,
        date == today ? l10n.levelReceiptIfCloses(math) : math,
      ),
    ];
  }

  Widget _none(MetricFormat format) => _Row(
    key: LevelReceiptKeys.effect,
    label: format.l10n.levelReceiptEffect,
    value: format.l10n.levelReceiptNone,
  );
}

class _Row extends StatelessWidget {
  const new({required this.label, required this.value, this.detail, super.key});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final detail = this.detail;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            Text.rich(
              TextSpan(
                text: value,
                children: [
                  if (detail != null)
                    TextSpan(
                      text: '  $detail',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textLabel,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
