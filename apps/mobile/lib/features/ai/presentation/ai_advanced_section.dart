import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_advanced_input.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiAdvancedKeys {
  static const toggle = Key('ai_advanced_toggle');
  static const maxTokens = Key('ai_advanced_max_tokens');
  static const priceIn = Key('ai_advanced_price_in');
  static const priceOut = Key('ai_advanced_price_out');
  static const currency = Key('ai_advanced_currency');
  static const tokenCap = Key('ai_advanced_token_cap');
  static const save = Key('ai_advanced_save');
  static const localNote = Key('ai_advanced_local_note');

  static Key timeout(int seconds) => Key('ai_advanced_timeout_$seconds');

  static Key structured(AiStructuredOutputMode mode) =>
      Key('ai_advanced_structured_${mode.name}');

  static Key streaming(AiStreamingMode mode) =>
      Key('ai_advanced_streaming_${mode.name}');

  static Key reasoning(AiReasoningEffort? effort) =>
      Key('ai_advanced_reasoning_${effort?.name ?? 'notSent'}');
}

const List<AiReasoningEffort?> _efforts = [null, ...AiReasoningEffort.values];

/// The parsed values of the number fields.
typedef _Typed = ({
  int tokens,
  int? cap,
  double? priceIn,
  double? priceOut,
  String currency,
});

/// Choices save on tap; the number fields save together with one Save,
/// which stays disabled while any of them is invalid.
class AiAdvancedSection extends ConsumerStatefulWidget {
  const new({required this.config, required this.locked, super.key});

  final AiConfig config;
  final bool locked;

  @override
  ConsumerState<AiAdvancedSection> createState() => _AiAdvancedSectionState();
}

class _AiAdvancedSectionState extends ConsumerState<AiAdvancedSection> {
  final _tokens = TextEditingController();
  final _cap = TextEditingController();
  final _priceIn = TextEditingController();
  final _priceOut = TextEditingController();
  final _currency = TextEditingController();
  var _open = false;

  List<TextEditingController> get _fields => [
    _tokens,
    _cap,
    _priceIn,
    _priceOut,
    _currency,
  ];

  @override
  void initState() {
    super.initState();
    _fill(widget.config);
    for (final c in _fields) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(AiConfig config) {
    _tokens.text = '${config.maxOutputTokens}';
    _cap.text = config.monthlyTokenCap?.toString() ?? '';
    _priceIn.text = formatAiPrice(config.inputPricePerMillion);
    _priceOut.text = formatAiPrice(config.outputPricePerMillion);
    _currency.text = config.priceCurrency;
  }

  _Typed? _typed() {
    final tokens = parseAiOutputTokens(_tokens.text);
    final cap = parseAiTokenCap(_cap.text);
    final priceIn = parseAiPrice(_priceIn.text);
    final priceOut = parseAiPrice(_priceOut.text);
    final currency = parseAiCurrency(_currency.text);
    if (tokens == null || cap == null || currency == null) return null;
    if (priceIn == null || priceOut == null) return null;
    return (
      tokens: tokens,
      cap: cap.value,
      priceIn: priceIn.value,
      priceOut: priceOut.value,
      currency: currency,
    );
  }

  static AiConfig _apply(AiConfig config, _Typed typed) => config.copyWith(
    maxOutputTokens: typed.tokens,
    monthlyTokenCap: typed.cap,
    clearMonthlyTokenCap: typed.cap == null,
    inputPricePerMillion: typed.priceIn,
    clearInputPrice: typed.priceIn == null,
    outputPricePerMillion: typed.priceOut,
    clearOutputPrice: typed.priceOut == null,
    priceCurrency: typed.currency,
  );

  /// Advanced edits keep the tested state: the profile belongs to the
  /// address and model, and forced modes are applied on top at run time.
  Future<void> _edit(AiConfig Function(AiConfig) change) =>
      ref.read(aiConfigProvider.notifier).edit(change);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TileGroup(
          children: [
            SettingsTile(
              key: AiAdvancedKeys.toggle,
              title: l10n.aiAdvancedTitle,
              detail: l10n.aiAdvancedCaption,
              leading: const Icon(Icons.tune_rounded),
              trailing: Icon(
                _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              ),
              onTap: () => setState(() => _open = !_open),
            ),
          ],
        ),
        if (_open) ..._controls(l10n),
      ],
    );
  }

  List<Widget> _controls(AppLocalizations l10n) {
    final config = widget.config;
    final locked = widget.locked;
    final compact = config.contextWindow == AiContextWindow.compact;
    return [
      const SizedBox(height: 16),
      _number(
        AiAdvancedKeys.maxTokens,
        _tokens,
        l10n.aiAdvancedMaxTokens,
        parseAiOutputTokens(_tokens.text) == null,
        l10n.aiAdvancedInvalid('tokens'),
      ),
      SectionHeader(l10n.aiAdvancedTimeout),
      ChoiceRow<int>(
        values: aiAllowedTimeoutSeconds,
        selected: config.requestTimeoutSeconds,
        label: l10n.measureSecondsLeft,
        keyOf: AiAdvancedKeys.timeout,
        onSelected: locked
            ? null
            : (s) =>
                  unawaited(_edit((c) => c.copyWith(requestTimeoutSeconds: s))),
      ),
      if (compact) ...[
        const SizedBox(height: 8),
        CaptionText(key: AiAdvancedKeys.localNote, l10n.aiLocalSoftnote),
      ],
      SectionHeader(l10n.aiAdvancedStructuredTitle),
      ChoiceRow<AiStructuredOutputMode>(
        values: AiStructuredOutputMode.values,
        selected: config.structuredOutputMode,
        label: (m) => l10n.aiAdvancedStructured(m.name),
        keyOf: AiAdvancedKeys.structured,
        onSelected: locked
            ? null
            : (m) =>
                  unawaited(_edit((c) => c.copyWith(structuredOutputMode: m))),
      ),
      SectionHeader(l10n.aiAdvancedStreamingTitle),
      ChoiceRow<AiStreamingMode>(
        values: AiStreamingMode.values,
        selected: config.streamingMode,
        label: (m) => l10n.aiAdvancedStructured(m.name),
        keyOf: AiAdvancedKeys.streaming,
        onSelected: locked
            ? null
            : (m) => unawaited(_edit((c) => c.copyWith(streamingMode: m))),
      ),
      SectionHeader(l10n.aiAdvancedReasoningTitle),
      ChoiceRow<AiReasoningEffort?>(
        values: _efforts,
        selected: config.reasoningEffort,
        label: (e) => l10n.aiAdvancedReasoning(e?.name ?? 'notSent'),
        keyOf: AiAdvancedKeys.reasoning,
        onSelected: locked
            ? null
            : (e) => unawaited(
                _edit(
                  (c) => c.copyWith(
                    reasoningEffort: e,
                    clearReasoningEffort: e == null,
                  ),
                ),
              ),
      ),
      const SizedBox(height: 16),
      _number(
        AiAdvancedKeys.priceIn,
        _priceIn,
        l10n.aiAdvancedPriceIn,
        parseAiPrice(_priceIn.text) == null,
        l10n.aiAdvancedInvalid('price'),
        decimal: true,
      ),
      const SizedBox(height: 12),
      _number(
        AiAdvancedKeys.priceOut,
        _priceOut,
        l10n.aiAdvancedPriceOut,
        parseAiPrice(_priceOut.text) == null,
        l10n.aiAdvancedInvalid('price'),
        decimal: true,
      ),
      const SizedBox(height: 12),
      _field(
        AiAdvancedKeys.currency,
        _currency,
        l10n.aiAdvancedCurrency,
        parseAiCurrency(_currency.text) == null
            ? l10n.aiAdvancedInvalid('currency')
            : null,
        TextInputType.text,
      ),
      const SizedBox(height: 6),
      CaptionText(l10n.aiAdvancedPriceHelp),
      const SizedBox(height: 16),
      _number(
        AiAdvancedKeys.tokenCap,
        _cap,
        l10n.aiAdvancedTokenCap,
        parseAiTokenCap(_cap.text) == null,
        l10n.aiAdvancedInvalid('cap'),
      ),
      const SizedBox(height: 6),
      CaptionText(l10n.aiAdvancedTokenCapNone),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton.tonal(
          key: AiAdvancedKeys.save,
          onPressed: _saveAction(config),
          child: Text(l10n.workoutSave),
        ),
      ),
    ];
  }

  VoidCallback? _saveAction(AiConfig config) {
    final typed = _typed();
    if (widget.locked || typed == null) return null;
    if (_apply(config, typed) == config) return null;
    return () => unawaited(_edit((c) => _apply(c, typed)));
  }

  Widget _number(
    Key key,
    TextEditingController controller,
    String label,
    bool invalid,
    String error, {
    bool decimal = false,
  }) => _field(
    key,
    controller,
    label,
    invalid ? error : null,
    TextInputType.numberWithOptions(decimal: decimal),
  );

  Widget _field(
    Key key,
    TextEditingController controller,
    String label,
    String? error,
    TextInputType keyboard,
  ) => TextField(
    key: key,
    controller: controller,
    enabled: !widget.locked,
    keyboardType: keyboard,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      errorText: error,
      errorMaxLines: 3,
    ),
  );
}
