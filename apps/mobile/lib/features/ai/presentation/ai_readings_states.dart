import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/presentation/ai_test_connection_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiReadingStateKeys {
  static const noModel = Key('ai_readings_no_model');
  static const guide = Key('ai_readings_guide');
  static const connection = Key('ai_readings_connection');
  static const untested = Key('ai_readings_untested');
  static const test = Key('ai_readings_test');
  static const early = Key('ai_readings_early');
  static const stale = Key('ai_readings_stale');
  static const sample = Key('ai_readings_sample');
}

/// No address, no model, or a required key missing: nothing can be sent.
bool aiNoConnection(AiConfig config) =>
    config.normalizedUrl == null ||
    config.trimmedModel.isEmpty ||
    (config.preset.keyRequired && config.keyLastFour == null);

class AiNoModelCard extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      key: AiReadingStateKeys.noModel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            l10n.aiReadingsNoModelTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          BodyText(l10n.aiReadingsNoModelBody),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: AiReadingStateKeys.guide,
                onPressed: () => context.go(AppPaths.settingsAiGuide),
                child: Text(l10n.aiGuideTitle),
              ),
              OutlinedButton(
                key: AiReadingStateKeys.connection,
                onPressed: () => context.go(AppPaths.settingsAiConnection),
                child: Text(l10n.aiGuideOpen),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AiUntestedCard extends StatelessWidget {
  const new({required this.config, super.key});

  final AiConfig config;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      key: AiReadingStateKeys.untested,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            l10n.aiReadingsUntestedTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          BodyText(l10n.aiTestNoData),
          FilledButton(
            key: AiReadingStateKeys.test,
            onPressed: () => unawaited(
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AiTestConnectionSheet(config: config),
              ),
            ),
            child: Text(l10n.aiTestButton),
          ),
        ],
      ),
    );
  }
}

class AiEarlyCard extends StatelessWidget {
  const new({required this.days, super.key});

  final int days;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      key: AiReadingStateKeys.early,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            l10n.aiReadingsEarlyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          BodyText(l10n.aiPreviewNotEnough(days)),
          CaptionText(l10n.aiReadingsEarlyNote),
        ],
      ),
    );
  }
}

class AiReadingNotice extends StatelessWidget {
  const new({required this.icon, required this.text, this.caption, super.key});

  final IconData icon;
  final String text;
  final String? caption;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: MetricCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Icon(icon),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                BodyText(text),
                if (caption case final c?) CaptionText(c),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
