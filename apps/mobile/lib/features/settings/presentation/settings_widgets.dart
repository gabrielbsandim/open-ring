import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';

class SectionHeader extends StatelessWidget {
  const new(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const new({
    required this.title,
    this.detail,
    this.value,
    this.valueColor,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    super.key,
  });

  final String title;
  final String? detail;
  final String? value;
  final Color? valueColor;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final icon = leading;
    final end = trailing;
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  if (icon != null) ...[icon, const SizedBox(width: 12)],
                  Expanded(child: _content(context)),
                  if (end != null) ...[const SizedBox(width: 8), end],
                  if (chevron) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: colors.textLabel),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final caption = detail;
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(color: colors.textPrimary),
        ),
        if (caption != null) CaptionText(caption),
      ],
    );
    final text = value;
    if (text == null) return label;
    final valueText = Text(
      text,
      textAlign: context.prefersSingleColumn ? TextAlign.start : TextAlign.end,
      style: numberStyle(
        theme.textTheme.bodyMedium,
        color: valueColor ?? colors.textPrimary,
      ),
    );
    if (context.prefersSingleColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label, const SizedBox(height: 4), valueText],
      );
    }
    return Row(
      children: [
        Expanded(child: label),
        const SizedBox(width: 12),
        Flexible(child: valueText),
      ],
    );
  }
}

class TileGroup extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MetricCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) Divider(height: 1, color: colors.surfaceBorder),
            child,
          ],
        ],
      ),
    );
  }
}

class ChoiceRow<T> extends StatelessWidget {
  const new({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.keyOf,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T>? onSelected;
  final Key Function(T value)? keyOf;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pick = onSelected;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            key: keyOf?.call(value),
            label: Text(label(value)),
            selected: value == selected,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            selectedColor: colors.textPrimary,
            backgroundColor: colors.surfaceInner,
            side: BorderSide(color: colors.strongBorder),
            labelStyle: TextStyle(
              color: value == selected ? colors.background : colors.textPrimary,
            ),
            onSelected: pick == null ? null : (_) => pick(value),
          ),
      ],
    );
  }
}

class AccentDot extends StatelessWidget {
  const new({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
