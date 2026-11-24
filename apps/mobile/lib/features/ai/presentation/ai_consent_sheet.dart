import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_consent_scope.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiConsentKeys {
  static const sheet = Key('ai_consent_sheet');
  static const added = Key('ai_consent_added');
  static const unencrypted = Key('ai_consent_unencrypted');
  static const tick = Key('ai_consent_tick');
  static const allow = Key('ai_consent_allow');
  static const cancel = Key('ai_consent_cancel');
}

String aiCategoryLabel(AppLocalizations l10n, AiDataCategory category) =>
    switch (category) {
      AiDataCategory.body => l10n.moduleBodyName,
      AiDataCategory.energy => l10n.energyTitle,
      AiDataCategory.goals => l10n.moduleGoalsName,
      AiDataCategory.food => l10n.foodTitle,
      AiDataCategory.imported => l10n.aiImportedTitle,
    };

/// Names the key only when one is stored; local servers often take none.
String aiConsentWhereLine(AppLocalizations l10n, AiConfig config) {
  final host = config.normalizedUrl?.asciiHost ?? '';
  if (config.keyLastFour == null) return l10n.aiConsentWhereNoKey(host);
  return l10n.aiConsentWhere(host);
}

/// True once a consent covering [payload] at the config's host is stored.
Future<bool> showAiConsentSheet(
  BuildContext context, {
  required AiConfig config,
  required BuiltAiPayload payload,
  required AiConsent? previous,
}) async {
  final granted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        AiConsentSheet(config: config, payload: payload, previous: previous),
  );
  return granted ?? false;
}

class AiConsentSheet extends ConsumerStatefulWidget {
  const new({
    required this.config,
    required this.payload,
    required this.previous,
    super.key,
  });

  final AiConfig config;
  final BuiltAiPayload payload;
  final AiConsent? previous;

  @override
  ConsumerState<AiConsentSheet> createState() => _AiConsentSheetState();
}

class _AiConsentSheetState extends ConsumerState<AiConsentSheet> {
  var _ticked = false;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = widget.config.normalizedUrl;
    final host = url?.asciiHost ?? '';
    final added = aiNewCategories(
      widget.previous,
      widget.config,
      widget.payload,
    );
    final colors = AppColors.of(context);
    return SafeArea(
      key: AiConsentKeys.sheet,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.aiConsentTitle(added.isEmpty ? 'first' : 'added', host),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (added.isNotEmpty) ...[
              const SizedBox(height: 12),
              MetricCard(
                key: AiConsentKeys.added,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CaptionText(l10n.aiConsentAdded),
                    for (final c in added) _line(aiCategoryLabel(l10n, c)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _line(l10n.aiConsentWhat),
            _line(aiConsentWhereLine(l10n, widget.config)),
            _line(l10n.aiConsentAfter(host)),
            _line(l10n.aiConsentModel),
            if (url?.isCleartext ?? false)
              Padding(
                key: AiConsentKeys.unencrypted,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_open_rounded, color: colors.heart),
                    const SizedBox(width: 12),
                    Expanded(child: BodyText(l10n.aiConsentUnencrypted)),
                  ],
                ),
              ),
            CheckboxListTile(
              key: AiConsentKeys.tick,
              value: _ticked,
              onChanged: (v) => setState(() => _ticked = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.aiConsentTick(host)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: AiConsentKeys.cancel,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.settingsDeleteCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: AiConsentKeys.allow,
                    onPressed: _ticked && !_busy
                        ? () => unawaited(_grant())
                        : null,
                    child: Text(l10n.permissionsAllow),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CaptionText(l10n.aiConsentScope),
          ],
        ),
      ),
    );
  }

  Widget _line(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_rounded,
          size: 20,
          color: AppColors.of(context).textLabel,
        ),
        const SizedBox(width: 12),
        Expanded(child: BodyText(text)),
      ],
    ),
  );

  Future<void> _grant() async {
    setState(() => _busy = true);
    final consent = aiConsentFor(
      config: widget.config,
      payload: widget.payload,
      previous: widget.previous,
      at: ref.read(clockProvider)(),
    );
    try {
      await ref.read(aiConfigProvider.notifier).recordConsent(consent);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
