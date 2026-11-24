import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiGuideKeys {
  static const local = Key('ai_guide_local');
  static const cost = Key('ai_guide_cost');
  static const open = Key('ai_guide_open');

  static Key step(int number) => Key('ai_guide_step_$number');
}

class AiGuideScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final steps = [
      (l10n.aiGuideStep1Title, l10n.aiGuideStep1Body),
      (l10n.aiGuideStep2Title, l10n.aiGuideStep2Body),
      (l10n.aiGuideStep3Title, l10n.aiGuideStep3Body),
      (l10n.aiGuideStep4Title, l10n.aiGuideStep4Body),
    ];
    return AppPage(
      title: l10n.aiGuideTitle,
      subtitle: l10n.aiGuideLead,
      children: [
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, (title, body)) in steps.indexed)
                _GuideStep(
                  key: AiGuideKeys.step(index + 1),
                  number: index + 1,
                  title: title,
                  body: body,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        MetricCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ExpansionTile(
            key: AiGuideKeys.local,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            shape: const Border(),
            leading: Icon(Icons.computer_rounded, color: colors.textLabel),
            title: Text(l10n.aiGuideLocalTitle),
            children: [BodyText(l10n.aiGuideLocalBody)],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          key: AiGuideKeys.cost,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: colors.textLabel),
            const SizedBox(width: 12),
            Expanded(child: BodyText(l10n.aiGuideCost)),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: AiGuideKeys.open,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => context.go(AppPaths.settingsAiConnection),
          child: Text(l10n.aiGuideOpen),
        ),
      ],
    );
  }
}

class _GuideStep extends StatelessWidget {
  const new({
    required this.number,
    required this.title,
    required this.body,
    super.key,
  });

  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: colors.textPrimary,
            foregroundColor: colors.background,
            child: Text('$number'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                BodyText(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
