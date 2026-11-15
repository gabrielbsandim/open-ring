import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/application/celebration_providers.dart';
import 'package:open_ring/features/open_score/presentation/level_block.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class LevelCelebrationKeys {
  static const card = Key('level_celebration');
  static const title = Key('level_celebration_title');
  static const open = Key('level_celebration_open');
  static const close = Key('level_celebration_close');
}

String celebrationTitle(AppLocalizations l10n, LevelCelebration earned) {
  if (earned.goal == null) return l10n.levelCeleBest;
  return earned.hasBest ? l10n.levelCeleBoth : l10n.levelCeleGoal;
}

List<String> celebrationLines(MetricFormat format, LevelCelebration earned) {
  final l10n = format.l10n;
  return [
    if (earned.goal case final goal?) l10n.levelCeleGoalLine(goal),
    if ((earned.day, earned.previousDay) case (final day?, final previous?))
      l10n.levelCeleDayLine(
        day.score,
        previous.score,
        format.monthDay(previous.date),
      ),
    if ((earned.level, earned.previousLevel) case (
      final level?,
      final previous?,
    ))
      l10n.levelCeleLevelLine(
        levelNumber(format, level.level),
        levelNumber(format, previous.level),
        format.monthDay(previous.date),
      ),
  ];
}

/// Shows nothing until yesterday earned something, and nothing again once
/// the user closes it for the day.
class LevelCelebrationCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(levelCelebrationProvider).value;
    if (shown == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: cardGap),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: MetricCard(
          key: LevelCelebrationKeys.card,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: ExcludeSemantics(child: _Seal()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        key: LevelCelebrationKeys.title,
                        celebrationTitle(l10n, shown.earned),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final line in celebrationLines(format, shown.earned))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: BodyText(line),
                      ),
                    TextButton(
                      key: LevelCelebrationKeys.open,
                      onPressed: () => context.go(AppPaths.dayScoreLevel),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(l10n.levelCeleOpen),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: LevelCelebrationKeys.close,
                tooltip: l10n.levelCeleClose,
                onPressed: () => ref
                    .read(celebrationClosedProvider.notifier)
                    .close(shown.today),
                icon: Icon(Icons.close_rounded, color: colors.textLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Seal extends StatelessWidget {
  const new();

  static const _size = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: SizedBox.square(
        dimension: _size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.textPrimary,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded, size: 20, color: colors.surface),
        ),
      ),
    );
  }
}
