import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class DayTagSheetKeys {
  static const none = Key('day_tag_none');
  static const close = Key('day_tag_close');

  static Key option(DayTag tag) => Key('day_tag_${tag.name}');
}

typedef _Choice = ({DayTag? tag});

String dayTagLabel(AppLocalizations l10n, DayTag tag) => switch (tag) {
  DayTag.sick => l10n.dayTagSick,
  DayTag.travel => l10n.dayTagTravel,
  DayTag.rest => l10n.dayTagRest,
};

IconData dayTagIcon(DayTag tag) => switch (tag) {
  DayTag.sick => Icons.thermostat_rounded,
  DayTag.travel => Icons.luggage_outlined,
  DayTag.rest => Icons.weekend_outlined,
};

String _hint(AppLocalizations l10n, DayTag tag) => switch (tag) {
  DayTag.sick => l10n.dayTagSickHint,
  DayTag.travel => l10n.dayTagTravelHint,
  DayTag.rest => l10n.dayTagRestHint,
};

/// Asks for the tag of [date], saves the answer and offers to undo it.
Future<void> showDayTagSheet(
  BuildContext context,
  WidgetRef ref, {
  required LocalDate date,
  required LocalDate today,
  required DayTag? current,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final format = MetricFormat.of(context);
  final l10n = format.l10n;
  final log = ref.read(dayTagLogProvider.notifier);
  final picked = await showModalBottomSheet<_Choice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.of(context).surface,
    builder: (context) => SafeArea(
      child: DayTagSheet(
        title: date == today
            ? l10n.dayTagSheetToday
            : l10n.dayTagSheetDay(format.date(date)),
        current: current,
      ),
    ),
  );
  if (picked == null || picked.tag == current) return;
  final tag = picked.tag;
  if (!await log.set(date, tag)) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          tag == null
              ? l10n.dayTagRemoved
              : l10n.dayTagSet(dayTagLabel(l10n, tag)),
        ),
        action: SnackBarAction(
          label: l10n.bodyEntryUndo,
          onPressed: () => unawaited(log.set(date, current)),
        ),
      ),
    );
}

class DayTagSheet extends StatelessWidget {
  const new({required this.title, required this.current, super.key});

  final String title;
  final DayTag? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          BodyText(l10n.dayTagSheetLead),
          const SizedBox(height: 8),
          for (final tag in DayTag.values)
            _Option(
              key: DayTagSheetKeys.option(tag),
              icon: dayTagIcon(tag),
              title: dayTagLabel(l10n, tag),
              hint: _hint(l10n, tag),
              selected: current == tag,
              onTap: () => Navigator.of(context).pop<_Choice>((tag: tag)),
            ),
          _Option(
            key: DayTagSheetKeys.none,
            icon: Icons.check_rounded,
            title: l10n.dayTagNone,
            hint: l10n.dayTagNoneHint,
            selected: current == null,
            onTap: () => Navigator.of(context).pop<_Choice>((tag: null)),
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            key: DayTagSheetKeys.close,
            label: MaterialLocalizations.of(context).closeButtonLabel,
            onPressed: () => Navigator.of(context).pop<_Choice>(),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$title. $hint',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(icon, color: colors.textLabel),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      CaptionText(hint),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.textPrimary : colors.textLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tag of a day as a dashed chip: visible, and set aside.
class DayTagChip extends StatelessWidget {
  const new({required this.tag, super.key});

  final DayTag tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return CustomPaint(
      painter: DashedBorderPainter(color: colors.textLabel, radius: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(dayTagIcon(tag), size: 14, color: colors.textPrimary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                dayTagLabel(l10n, tag),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  const new({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 4.0;
  static const _gap = 3.0;
  static const _width = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(_width / 2),
          Radius.circular(radius),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
