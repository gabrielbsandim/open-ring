import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_consent_scope.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/ai_consent_sheet.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiPreviewKeys {
  static const readable = Key('ai_preview_readable');
  static const exact = Key('ai_preview_exact');
  static const system = Key('ai_preview_system');
  static const user = Key('ai_preview_user');
  static const copy = Key('ai_preview_copy');
  static const notEncrypted = Key('ai_preview_not_encrypted');
  static const notEnough = Key('ai_preview_not_enough');
  static const ask = Key('ai_preview_ask');
  static const given = Key('ai_preview_given');
  static const withdraw = Key('ai_preview_withdraw');

  static Key section(String name) => Key('ai_preview_section_$name');
}

/// Both tabs render the [BuiltAiPayload] the run controller sends, so the
/// readable view and the exact text cannot disagree.
class AiContextPreviewScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AiContextPreviewScreen> createState() =>
      _AiContextPreviewScreenState();
}

class _AiContextPreviewScreenState
    extends ConsumerState<AiContextPreviewScreen> {
  var _exact = false;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(aiConfigProvider).value;
    final result = ref.watch(aiPayloadProvider).value;
    final consent = ref.watch(aiConsentProvider).value;
    final host = config?.normalizedUrl?.asciiHost ?? '';
    return AppPage(
      title: l10n.aiPreviewTitle,
      subtitle: l10n.aiPreviewLead(host),
      children: switch ((config, result)) {
        (final AiConfig c, AiPayloadReady(:final payload)) => _body(
          l10n,
          c,
          payload,
          consent,
        ),
        (_, AiPayloadNotEnoughData(:final days)) => [
          BodyText(key: AiPreviewKeys.notEnough, l10n.aiPreviewNotEnough(days)),
        ],
        _ => const [SizedBox(height: 96)],
      },
    );
  }

  List<Widget> _body(
    AppLocalizations l10n,
    AiConfig config,
    BuiltAiPayload payload,
    AiConsent? consent,
  ) {
    final url = config.normalizedUrl;
    final host = url?.asciiHost ?? '';
    final cleartext = url?.isCleartext ?? false;
    final heart = AppColors.of(context).heart;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(
            avatar: cleartext
                ? Icon(Icons.lock_open_rounded, color: heart)
                : const Icon(Icons.lock_outline_rounded),
            label: Text(host),
          ),
          Chip(label: Text(config.trimmedModel)),
          Chip(label: Text(l10n.aiDetailLevel(config.detailLevel.name))),
          Chip(label: Text(l10n.aiPreviewTokens(payload.estimatedTokens))),
        ],
      ),
      if (cleartext) ...[
        const SizedBox(height: 8),
        CaptionText(
          key: AiPreviewKeys.notEncrypted,
          l10n.aiConnectionNotEncrypted,
        ),
      ],
      const SizedBox(height: 16),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: Text(key: AiPreviewKeys.readable, l10n.aiPreviewReadable),
          ),
          ButtonSegment(
            value: true,
            label: Text(key: AiPreviewKeys.exact, l10n.aiPreviewExact),
          ),
        ],
        selected: {_exact},
        onSelectionChanged: (s) => setState(() => _exact = s.first),
      ),
      const SizedBox(height: 16),
      if (_exact) ..._exactText(l10n, payload),
      if (!_exact)
        for (final MapEntry(:key, :value) in payload.contextMap.entries)
          _section(l10n, key, value),
      const SizedBox(height: 16),
      CaptionText(l10n.aiPreviewNotSent(host)),
      const SizedBox(height: 24),
      ..._consent(l10n, config, payload, consent, host),
    ];
  }

  List<Widget> _exactText(AppLocalizations l10n, BuiltAiPayload payload) => [
    const SectionHeader('system'),
    _mono(payload.systemPrompt, AiPreviewKeys.system),
    const SectionHeader('user'),
    _mono(payload.userMessage, AiPreviewKeys.user),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      key: AiPreviewKeys.copy,
      icon: const Icon(Icons.copy_rounded),
      label: Text(l10n.aiPreviewCopy),
      onPressed: () => unawaited(
        Clipboard.setData(
          ClipboardData(
            text: '${payload.systemPrompt}\n\n${payload.userMessage}',
          ),
        ),
      ),
    ),
  ];

  Widget _mono(String text, Key key) => MetricCard(
    child: SelectableText(
      key: key,
      text,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );

  Widget _section(AppLocalizations l10n, String name, Object? value) => Padding(
    key: AiPreviewKeys.section(name),
    padding: const EdgeInsets.only(bottom: 12),
    child: MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CaptionText(_sectionLabel(l10n, name)),
          const SizedBox(height: 6),
          _sectionBody(value),
        ],
      ),
    ),
  );

  Widget _sectionBody(Object? value) {
    if (value is Map && _isColumns(value)) return _table(value);
    if (value is Map) {
      return BodyText(
        [for (final e in value.entries) '${e.key}: ${_flat(e.value)}']
            .join('\n'),
      );
    }
    if (value is List) return BodyText(value.map(_flat).join('\n'));
    return BodyText(_flat(value));
  }

  Widget _table(Map<Object?, Object?> columns) {
    final keys = columns.keys.toList();
    final rows = (columns[keys.first]! as List).length;
    String cell(Object? key, int row) => _flat((columns[key]! as List)[row]);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 32,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 32,
        columns: [for (final k in keys) DataColumn(label: Text('$k'))],
        rows: [
          for (var r = 0; r < rows; r++)
            DataRow(cells: [for (final k in keys) DataCell(Text(cell(k, r)))]),
        ],
      ),
    );
  }

  List<Widget> _consent(
    AppLocalizations l10n,
    AiConfig config,
    BuiltAiPayload payload,
    AiConsent? consent,
    String host,
  ) {
    if (!aiConsentCoversPayload(consent, config, payload)) {
      return [
        FilledButton(
          key: AiPreviewKeys.ask,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy
              ? null
              : () => unawaited(
                  showAiConsentSheet(
                    context,
                    config: config,
                    payload: payload,
                    previous: consent,
                  ),
                ),
          child: Text(l10n.aiConsentAsk(host)),
        ),
      ];
    }
    final date = MaterialLocalizations.of(context).formatMediumDate(
      DateTime.fromMillisecondsSinceEpoch(consent!.consentedAtUtcMs),
    );
    return [
      BodyText(key: AiPreviewKeys.given, l10n.aiConsentGiven(host, date)),
      const SizedBox(height: 12),
      OutlinedButton(
        key: AiPreviewKeys.withdraw,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _busy ? null : () => unawaited(_withdraw()),
        child: Text(l10n.aiConsentWithdraw),
      ),
    ];
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    try {
      await ref.read(aiConfigProvider.notifier).withdrawConsent();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

bool _isColumns(Map<Object?, Object?> map) {
  if (map.values.any((v) => v is! List)) return false;
  final lengths = {for (final v in map.values) (v! as List).length};
  return lengths.length == 1 && lengths.first > 0;
}

String _flat(Object? value) => switch (value) {
  null => 'null',
  final Map<Object?, Object?> m => [
    for (final e in m.entries) '${e.key} ${_flat(e.value)}',
  ].join(' · '),
  final List<Object?> l => l.map(_flat).join(', '),
  _ => '$value',
};

String _sectionLabel(AppLocalizations l10n, String name) => switch (name) {
  'profile' => l10n.profileTitle,
  'workouts' => l10n.sourcesWorkouts,
  'weigh_ins' => l10n.moduleBodyName,
  'energy' => l10n.energyTitle,
  'goal' || 'plan' => l10n.moduleGoalsName,
  'food' => l10n.foodTitle,
  _ => name,
};
