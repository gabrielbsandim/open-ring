import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';

const zoneCount = 5;

class WorkoutGrid extends StatelessWidget {
  const new({required this.children, this.columns = 3, super.key});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    if (context.prefersSingleColumn || columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      if (start > 0) rows.add(const SizedBox(height: 10));
      rows.add(_row(start));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _row(int start) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < columns; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: start + i < children.length
                ? children[start + i]
                : const SizedBox.shrink(),
          ),
        ],
      ],
    ),
  );
}

class WorkoutMetricTile extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.unit,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final String unit;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final single = context.prefersSingleColumn;
    final valueText = Text(
      value,
      textAlign: single ? TextAlign.start : TextAlign.center,
      style: numberStyle(
        single
            ? theme.textTheme.headlineSmall
            : theme.textTheme.titleLarge?.copyWith(fontSize: 20),
        color: valueColor ?? colors.textPrimary,
      ),
    );
    final unitText = CaptionText(
      unit,
      textAlign: single ? TextAlign.start : TextAlign.center,
    );
    return MetricCard(
      padding: single
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: single
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            CaptionText(
              label,
              textAlign: single ? TextAlign.start : TextAlign.center,
            ),
            const SizedBox(height: 2),
            if (single)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [valueText, unitText],
              ),
            if (!single) ...[valueText, unitText],
          ],
        ),
      ),
    );
  }
}

class ZoneBar extends StatelessWidget {
  const new({required this.zone, required this.semanticsLabel, super.key});

  final int? zone;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel,
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (var i = 1; i <= zoneCount; i++) ...[
              if (i > 1) const SizedBox(width: 3),
              Expanded(
                child: Container(
                  height: i == zone ? 10 : 8,
                  decoration: BoxDecoration(
                    color: i == zone ? colors.heart : colors.track,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const new({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class DotLabel extends StatelessWidget {
  const new({required this.color, required this.text, super.key});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final lineHeight = MediaQuery.textScalerOf(context)
        .scale((style?.fontSize ?? 14) * (style?.height ?? 1.4));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: lineHeight,
          child: Center(child: StatusDot(color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

class AccentButton extends StatelessWidget {
  const new({
    required this.label,
    required this.color,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final glyph = icon;
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        backgroundColor: color,
        foregroundColor: colors.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            Icon(glyph, size: 20),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class NoticeCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.accent,
    required this.title,
    this.body,
    this.actions = const [],
    this.border,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String? body;
  final List<Widget> actions;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = body;
    return Semantics(
      liveRegion: true,
      child: _BorderedCard(
        border: border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (text != null) ...[
                        const SizedBox(height: 4),
                        BodyText(text),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            for (final action in actions) ...[
              const SizedBox(height: 10),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class _BorderedCard extends StatelessWidget {
  const new({required this.child, this.border});

  final Widget child;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border ?? colors.surfaceBorder),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class ButtonPair extends StatelessWidget {
  const new({required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (context.prefersSingleColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 10), second],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: 10),
          Expanded(child: second),
        ],
      ),
    );
  }
}
