import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

const onboardingSteps = 4;

String healthPlatformName() => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS => 'Apple Health',
  _ => 'Health Connect',
};

class OnboardingPage extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.intro,
    this.step,
    this.label,
    this.trailing,
    this.hero,
    super.key,
  });

  final String title;
  final String? intro;
  final int? step;
  final String? label;
  final Widget? trailing;
  final Widget? hero;
  final List<Widget> children;

  // The title lives in the scrolling body, not an AppBar, so it can grow and
  // wrap with the user's font size like every other screen.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final caption = switch (step) {
      null => label,
      final step => l10n.onboardingStep(step, onboardingSteps),
    };
    final lead = intro;
    final art = hero;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (canPop || caption != null || trailing != null)
              _Header(canPop: canPop, caption: caption, trailing: trailing),
            const SizedBox(height: 8),
            if (art != null) ...[art, const SizedBox(height: 16)],
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.headlineMedium),
            ),
            if (lead != null) ...[const SizedBox(height: 10), BodyText(lead)],
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const new({
    required this.canPop,
    required this.caption,
    required this.trailing,
  });

  final bool canPop;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = caption;
    final parts = [
      if (text != null)
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.of(context).textLabel),
        ),
      ?trailing,
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          if (canPop) const BackButton(),
          if (canPop) const SizedBox(width: 4),
          if (parts.isNotEmpty)
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: parts,
              ),
            ),
        ],
      ),
    );
  }
}

class PrimaryAction extends StatelessWidget {
  const new({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: Theme.of(context).textTheme.titleSmall,
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class QuietAction extends StatelessWidget {
  const new({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: AppColors.of(context).textSecondary,
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class InfoNote extends StatelessWidget {
  const new({
    required this.icon,
    required this.text,
    this.accent,
    this.lead,
    this.live = false,
    super.key,
  });

  final IconData icon;
  final String text;
  final String? lead;
  final Color? accent;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final strong = lead;
    return Semantics(
      liveRegion: live,
      container: true,
      child: MetricCard(
        color: colors.surfaceInner,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: accent ?? colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (strong != null)
                      TextSpan(
                        text: '$strong ',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    TextSpan(text: text),
                  ],
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NumberedTip extends StatelessWidget {
  const new({required this.number, required this.body, this.title, super.key});

  final int number;
  final String? title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final heading = title;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surfaceInner,
                border: Border.all(color: colors.strongBorder),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '$number',
                style: numberStyle(
                  theme.textTheme.bodySmall,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (heading != null)
                    Text(
                      heading,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (heading != null) const SizedBox(height: 2),
                  BodyText(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HeroBadge extends StatelessWidget {
  const new({required this.icon, required this.accent, super.key});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: colors.surfaceInner,
          shape: BoxShape.circle,
          border: Border.all(color: colors.strongBorder),
        ),
        child: Icon(icon, size: 30, color: accent),
      ),
    );
  }
}
