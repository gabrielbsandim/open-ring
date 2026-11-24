import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiConnectionKeys {
  static const service = Key('ai_connection_service');
  static const address = Key('ai_connection_address');
  static const requestsGoTo = Key('ai_connection_requests_go_to');
  static const notEncrypted = Key('ai_connection_not_encrypted');
  static const apiKey = Key('ai_connection_api_key');
  static const keySaved = Key('ai_connection_key_saved');
  static const keyReplace = Key('ai_connection_key_replace');
  static const keyHelp = Key('ai_connection_key_help');
  static const model = Key('ai_connection_model');
  static const save = Key('ai_connection_save');
  static const switchDialog = Key('ai_connection_switch_dialog');
  static const switchConfirm = Key('ai_connection_switch_confirm');
  static const switchCancel = Key('ai_connection_switch_cancel');

  static Key preset(AiProviderPreset preset) =>
      Key('ai_connection_preset_${preset.name}');
}

String aiPresetLabel(AppLocalizations l10n, AiProviderPreset preset) =>
    switch (preset) {
      AiProviderPreset.openAi => 'OpenAI',
      AiProviderPreset.openRouter => 'OpenRouter',
      AiProviderPreset.groq => 'Groq',
      AiProviderPreset.gemini => 'Google Gemini',
      AiProviderPreset.anthropic => 'Anthropic',
      AiProviderPreset.ollama => l10n.aiConnectionPresetLocal('Ollama'),
      AiProviderPreset.lmStudio => l10n.aiConnectionPresetLocal('LM Studio'),
      AiProviderPreset.custom => l10n.aiConnectionPresetCustom,
    };

/// The inline refusal for a typed base URL, or null when it is empty or valid.
String? aiBaseUrlRefusal(AppLocalizations l10n, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final result = BaseUrlPolicy.parse(trimmed);
  if (result is! BaseUrlRejected) return null;
  // Uri resolves userinfo the way a client would, so this names the real target.
  final host = Uri.tryParse(trimmed)?.host ?? '';
  final shown = host.isEmpty ? trimmed : host;
  return switch (result.reason) {
    BaseUrlRejection.publicCleartext => l10n.aiConnectionRefusalCleartext(
      shown,
    ),
    BaseUrlRejection.hasUserInfo => l10n.aiConnectionRefusalUserInfo(shown),
    _ => l10n.aiConnectionRefusalInvalid,
  };
}

NormalizedBaseUrl? _parsedUrl(String raw) =>
    switch (BaseUrlPolicy.parse(raw.trim())) {
      BaseUrlOk(:final url) => url,
      BaseUrlRejected() => null,
    };

class AiConnectionScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AiConnectionScreen> createState() => _AiConnectionScreenState();
}

class _AiConnectionScreenState extends ConsumerState<AiConnectionScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  AiProviderPreset _preset = AiProviderPreset.openAi;
  var _loaded = false;
  var _replacingKey = false;
  var _busy = false;

  @override
  void dispose() {
    for (final c in [_url, _key, _model]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  void _load(AiConfig config) {
    if (_loaded) return;
    _loaded = true;
    _preset = config.preset;
    _url.text = config.baseUrl;
    _model.text = config.model;
    // Listening starts after the first fill, which runs inside build.
    for (final c in [_url, _key, _model]) {
      c.addListener(_changed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(aiConfigProvider);
    return AppPage(
      title: l10n.aiConnectionTitle,
      subtitle: l10n.aiConnectionLead,
      children: _body(l10n, config),
    );
  }

  List<Widget> _body(AppLocalizations l10n, AsyncValue<AiConfig> config) {
    if (config.hasValue) {
      final value = config.requireValue;
      _load(value);
      return _form(l10n, value);
    }
    if (config.hasError) return [BodyText(l10n.metricLoadError)];
    return const [SizedBox(height: 96)];
  }

  List<Widget> _form(AppLocalizations l10n, AiConfig config) {
    final url = _parsedUrl(_url.text);
    return [
      TileGroup(
        children: [
          SettingsTile(
            key: AiConnectionKeys.service,
            title: l10n.aiConnectionService,
            value: aiPresetLabel(l10n, _preset),
            chevron: true,
            onTap: _busy ? null : () => unawaited(_pickPreset(config)),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ..._addressField(l10n, url),
      const SizedBox(height: 16),
      ..._keyField(l10n, config, url),
      const SizedBox(height: 16),
      TextField(
        key: AiConnectionKeys.model,
        controller: _model,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: l10n.aiConnectionModel),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: AiConnectionKeys.save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _canSave(config, url)
            ? () => unawaited(_save(config))
            : null,
        child: Text(l10n.workoutSave),
      ),
    ];
  }

  List<Widget> _addressField(AppLocalizations l10n, NormalizedBaseUrl? url) {
    final colors = AppColors.of(context);
    final cleartext = url?.isCleartext ?? false;
    final hint = _preset.placeholderUrl;
    return [
      TextField(
        key: AiConnectionKeys.address,
        controller: _url,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: l10n.aiConnectionAddress,
          hintText: hint.isEmpty ? 'https://' : hint,
          prefixIcon: Icon(
            cleartext ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
          ),
          errorText: aiBaseUrlRefusal(l10n, _url.text),
          errorMaxLines: 4,
        ),
      ),
      if (url != null) ...[
        const SizedBox(height: 6),
        CaptionText(
          key: AiConnectionKeys.requestsGoTo,
          l10n.aiConnectionRequestsGoTo('${url.chatCompletionsUri}'),
        ),
      ],
      if (cleartext) ...[
        const SizedBox(height: 8),
        Row(
          key: AiConnectionKeys.notEncrypted,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_open_rounded, size: 18, color: colors.heart),
            const SizedBox(width: 8),
            Expanded(child: BodyText(l10n.aiConnectionNotEncrypted)),
          ],
        ),
      ],
    ];
  }

  List<Widget> _keyField(
    AppLocalizations l10n,
    AiConfig config,
    NormalizedBaseUrl? url,
  ) {
    final label = _preset.keyRequired
        ? l10n.aiConnectionKey
        : l10n.aiConnectionKeyOptional;
    final lastFour = config.keyLastFour;
    final host = url?.asciiHost;
    return [
      if (lastFour != null && !_replacingKey)
        _savedKey(l10n, label, lastFour)
      else
        TextField(
          key: AiConnectionKeys.apiKey,
          controller: _key,
          enabled: !_busy,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.key_rounded),
          ),
        ),
      if (host != null) ...[
        const SizedBox(height: 6),
        CaptionText(
          key: AiConnectionKeys.keyHelp,
          l10n.aiConnectionKeyHelp(host),
        ),
      ],
    ];
  }

  Widget _savedKey(AppLocalizations l10n, String label, String lastFour) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.key_rounded),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              key: AiConnectionKeys.keySaved,
              l10n.aiConnectionKeySaved(lastFour.isEmpty ? 'hidden' : lastFour),
            ),
          ),
          TextButton(
            key: AiConnectionKeys.keyReplace,
            onPressed: _busy
                ? null
                : () => setState(() => _replacingKey = true),
            child: Text(l10n.aiConnectionKeyReplace),
          ),
        ],
      ),
    );
  }

  bool _canSave(AiConfig config, NormalizedBaseUrl? url) {
    if (_busy || url == null) return false;
    return _preset != config.preset ||
        _url.text.trim() != config.baseUrl ||
        _model.text.trim() != config.model ||
        _key.text.trim().isNotEmpty;
  }

  bool _hostMoves(AiConfig config, String nextUrl) =>
      config.keyLastFour != null &&
      config.hostKey != null &&
      _parsedUrl(nextUrl)?.hostKey != config.hostKey;

  Future<void> _pickPreset(AiConfig config) async {
    final next = await showModalBottomSheet<AiProviderPreset>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _presetSheet(sheetCtx, _preset),
    );
    if (!mounted || next == null || next == _preset) return;
    // A preset without a fixed address defers the host move to a typed save.
    final moves = next.baseUrl.isNotEmpty && _hostMoves(config, next.baseUrl);
    if (moves && !await _confirmSwitch(config)) return;
    setState(() {
      _preset = next;
      _url.text = next.baseUrl;
      _model.clear();
      _key.clear();
      _replacingKey = false;
    });
    if (moves) await _persist(config);
  }

  Future<void> _save(AiConfig config) async {
    if (_hostMoves(config, _url.text) && !await _confirmSwitch(config)) {
      return;
    }
    await _persist(config);
  }

  Future<bool> _confirmSwitch(AiConfig config) async {
    final host = config.normalizedUrl?.asciiHost ?? config.baseUrl;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => _switchDialog(dialogCtx, host),
    );
    return mounted && ok == true;
  }

  Future<void> _persist(AiConfig config) async {
    setState(() => _busy = true);
    try {
      final controller = ref.read(aiConfigProvider.notifier);
      await controller.save(
        _withPresetDefaults(config)
            .copyWith(baseUrl: _url.text.trim(), model: _model.text.trim()),
      );
      final apiKey = _key.text.trim();
      if (apiKey.isNotEmpty) await controller.setApiKey(apiKey);
      _key.clear();
      _replacingKey = false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  AiConfig _withPresetDefaults(AiConfig config) {
    if (config.preset == _preset) return config;
    final window = _preset.defaultCompactContext
        ? AiContextWindow.compact
        : AiContextWindow.standard;
    return config.copyWith(
      preset: _preset,
      requestTimeoutSeconds: _preset.defaultTimeoutSeconds,
      contextWindow: window,
    );
  }
}

Widget _presetSheet(BuildContext context, AiProviderPreset current) {
  final l10n = AppLocalizations.of(context);
  final colors = AppColors.of(context);
  return SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.aiConnectionService,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          for (final preset in AiProviderPreset.values)
            ListTile(
              key: AiConnectionKeys.preset(preset),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                preset.isLocal
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
                color: colors.textLabel,
              ),
              title: Text(aiPresetLabel(l10n, preset)),
              trailing: preset == current
                  ? Icon(Icons.check_rounded, color: colors.textPrimary)
                  : null,
              selected: preset == current,
              onTap: () => Navigator.of(context).pop(preset),
            ),
        ],
      ),
    ),
  );
}

Widget _switchDialog(BuildContext context, String host) {
  final l10n = AppLocalizations.of(context);
  final colors = AppColors.of(context);
  return AlertDialog(
    key: AiConnectionKeys.switchDialog,
    scrollable: true,
    title: Text(l10n.aiConnectionSwitchTitle),
    content: Text(l10n.aiConnectionSwitchBody(host)),
    actions: [
      TextButton(
        key: AiConnectionKeys.switchCancel,
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(l10n.settingsDeleteCancel),
      ),
      FilledButton(
        key: AiConnectionKeys.switchConfirm,
        style: FilledButton.styleFrom(
          backgroundColor: colors.heart,
          foregroundColor: colors.onAccent,
        ),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(l10n.aiConnectionSwitchConfirm),
      ),
    ],
  );
}
