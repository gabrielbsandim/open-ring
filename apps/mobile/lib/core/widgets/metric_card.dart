import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/text_scale.dart';

const cardGap = 12.0;

TextStyle? numberStyle(TextStyle? base, {Color? color}) => base?.copyWith(
  color: color,
  fontWeight: FontWeight.w600,
  fontFeatures: const [FontFeature.tabularFigures()],
);

class MetricCard extends StatelessWidget {
  const new({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: color ?? colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.surfaceBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AccentTitle extends StatelessWidget {
  const new({required this.title, required this.accent, super.key});

  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MetricRow extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.valueColor,
    this.delta,
    this.deltaColor,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? delta;
  final Color? deltaColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
    );
    final valueText = Text.rich(
      TextSpan(
        text: value,
        children: [
          if (delta case final delta?)
            TextSpan(
              text: ' $delta',
              style: TextStyle(color: deltaColor),
            ),
        ],
      ),
      style: numberStyle(
        theme.textTheme.bodyMedium,
        color: valueColor ?? colors.textPrimary,
      ),
    );
    if (context.prefersSingleColumn) {
      return MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [labelText, valueText],
        ),
      );
    }
    return MergeSemantics(
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [labelText, valueText],
        ),
      ),
    );
  }
}

class AdaptiveColumns extends StatelessWidget {
  const new({required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (context.prefersSingleColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          const SizedBox(height: cardGap),
          second,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: cardGap),
          Expanded(child: second),
        ],
      ),
    );
  }
}

class CaptionText extends StatelessWidget {
  const new(this.text, {this.color, this.textAlign, super.key});

  final String text;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: color ?? AppColors.of(context).textLabel),
    );
  }
}

class BodyText extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: AppColors.of(context).textSecondary, height: 1.45),
    );
  }
}
