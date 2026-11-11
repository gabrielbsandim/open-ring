import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class EmptyStateCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.accent,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String message;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final heading = title;
    final label = actionLabel;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: accent),
          const SizedBox(height: 12),
          if (heading != null)
            Semantics(
              header: true,
              child: Text(
                heading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          if (heading != null) const SizedBox(height: 4),
          BodyText(message),
          if (label != null) const SizedBox(height: 16),
          if (label != null)
            ActionButton(key: actionKey, label: label, onPressed: onAction),
        ],
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  const new({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.color,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        backgroundColor: colors.surfaceInner,
        foregroundColor: color ?? colors.textPrimary,
        side: BorderSide(color: colors.strongBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class EstimateNote extends StatelessWidget {
  const new({this.lead, super.key});

  static const noteKey = Key('estimate_note');

  final String? lead;

  @override
  Widget build(BuildContext context) {
    final note = AppLocalizations.of(context).metricEstimateNote;
    final text = lead;
    return CaptionText(key: noteKey, text == null ? note : '$text $note');
  }
}

class AsyncBody<T> extends StatelessWidget {
  const new({required this.value, required this.builder, super.key});

  final AsyncValue<T> value;
  final Widget Function(T value) builder;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) {
      return EmptyStateCard(
        icon: Icons.error_outline_rounded,
        accent: AppColors.of(context).heart,
        message: AppLocalizations.of(context).metricLoadError,
      );
    }
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
