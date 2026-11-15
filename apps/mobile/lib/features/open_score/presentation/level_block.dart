import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/domain/level_view.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class LevelBlockKeys {
  static const block = Key('level_block');
  static const title = Key('level_block_title');
  static const value = Key('level_block_value');
  static const caption = Key('level_block_caption');
  static const gauge = Key('level_block_gauge');
}

// How far from the line the gauge runs out, in points.
const _gaugeSpan = 20.0;
const _gaugeEdge = 0.03;

String levelNumber(MetricFormat format, double level) =>
    format.decimal(level, digits: 1);

String levelRate(MetricFormat format) =>
    format.l10n.metricPercent(format.decimal(levelAlpha * 100, digits: 1));

String levelSideTitle(AppLocalizations l10n, LevelSide side) => switch (side) {
  LevelSide.above => l10n.levelAbove,
  LevelSide.on => l10n.levelOn,
  LevelSide.below => l10n.levelBelow,
};

/// What the Level does if a day at [score] closes against [line].
String levelCloseText(MetricFormat format, double line, int score) {
  final after = levelAfter(line, score);
  final value = levelNumber(format, after);
  return switch (levelMove(line, after)) {
    LevelMove.up => format.l10n.levelCloseUp(value),
    LevelMove.down => format.l10n.levelCloseDown(value),
    LevelMove.same => format.l10n.levelCloseSame(value),
  };
}

String _where(MetricFormat format, double line, int score) {
  final diff = levelNumber(format, (score - line).abs());
  return switch (levelSide(score, line)) {
    LevelSide.above => format.l10n.levelTodayAbove(diff),
    LevelSide.on => format.l10n.levelTodayOn(score),
    LevelSide.below => format.l10n.levelTodayBelow(diff),
  };
}

typedef _Parts = ({String title, String trailing, String caption});

/// Where today stands against the Level, inside the Today card.
class LevelBlock extends StatelessWidget {
  const new({
    required this.track,
    required this.score,
    required this.tagged,
    required this.onOpen,
    super.key,
  });

  final LevelTrack track;
  final int? score;
  final bool tagged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final level = track.level;
    final score = this.score;
    final parts = _parts(format);
    final compared = level != null && score != null && !tagged;
    return Semantics(
      key: LevelBlockKeys.block,
      button: true,
      label: '${parts.title}. ${parts.trailing}. ${parts.caption}',
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceInner,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    Text(
                      key: LevelBlockKeys.title,
                      parts.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            key: LevelBlockKeys.value,
                            parts.trailing,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: colors.textLabel,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (level == null) ...[
                  LevelProgress(counted: track.counted),
                  const SizedBox(height: 8),
                ],
                if (compared) ...[
                  LevelGauge(
                    key: LevelBlockKeys.gauge,
                    score: score,
                    line: level,
                  ),
                  const SizedBox(height: 8),
                ],
                CaptionText(key: LevelBlockKeys.caption, parts.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _Parts _parts(MetricFormat format) {
    final l10n = format.l10n;
    final level = track.level;
    if (level == null) {
      return (
        title: l10n.levelBuildingTitle(track.missing),
        trailing: l10n.levelBuildingCount(track.counted, levelSeedDays),
        caption: l10n.levelBuildingCaption(levelSeedDays),
      );
    }
    final value = levelNumber(format, level);
    final trailing = l10n.levelValue(value);
    if (tagged) {
      return (
        title: l10n.levelTaggedTitle,
        trailing: trailing,
        caption: l10n.levelTaggedBody(value),
      );
    }
    final score = this.score;
    if (score == null) {
      return (
        title: l10n.levelNoScoreTitle,
        trailing: trailing,
        caption: l10n.levelNoScoreBody(value),
      );
    }
    final side = levelSide(score, level);
    return (
      title: levelSideTitle(l10n, side),
      trailing: trailing,
      caption: [
        _where(format, level, score),
        levelCloseText(format, level, score),
        if (side == LevelSide.below) l10n.levelBelowTail,
      ].join(' '),
    );
  }
}

class LevelProgress extends StatelessWidget {
  const new({required this.counted, super.key});

  final int counted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: ColoredBox(
          color: colors.strongBorder,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: (counted / levelSeedDays).clamp(0, 1).toDouble(),
            child: ColoredBox(color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// A bar centred on the Level, with a dot where the day's score sits.
class LevelGauge extends StatelessWidget {
  const new({required this.score, required this.line, super.key});

  final int score;
  final double line;

  // Half the bar is [_gaugeSpan] points; a score further out stays at the end.
  double get position =>
      (0.5 + (score - line) / _gaugeSpan / 2).clamp(_gaugeEdge, 1 - _gaugeEdge);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      height: 14,
      child: CustomPaint(
        painter: _GaugePainter(
          position: position,
          track: colors.strongBorder,
          mark: colors.textPrimary,
          tick: colors.textLabel,
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const new({
    required this.position,
    required this.track,
    required this.mark,
    required this.tick,
  });

  final double position;
  final Color track;
  final Color mark;
  final Color tick;

  static const _bar = 4.0;
  static const _dot = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final middle = size.width / 2;
    final x = size.width * position;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - _bar / 2, size.width, _bar),
          const Radius.circular(_bar / 2),
        ),
        Paint()..color = track,
      )
      ..drawRect(
        Rect.fromLTRB(
          x < middle ? x : middle,
          y - _bar / 2,
          x < middle ? middle : x,
          y + _bar / 2,
        ),
        Paint()..color = mark,
      )
      ..drawRect(
        Rect.fromLTWH(middle - 1, 0, 2, size.height),
        Paint()..color = tick,
      )
      ..drawCircle(Offset(x, y), _dot, Paint()..color = mark);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.position != position || old.mark != mark || old.track != track;
}
