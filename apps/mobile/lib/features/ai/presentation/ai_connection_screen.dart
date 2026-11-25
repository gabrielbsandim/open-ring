import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/ai_advanced_section.dart';
import 'package:open_ring/features/ai/presentation/ai_models_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_test_connection_sheet.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
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
  static const test = Key('ai_connection_test');
  static const testFillFirst = Key('ai_connection_test_fill_first');
  static const tested = Key('ai_connection_tested');
  static const presetNote = Key('ai_connection_preset_note');
  static const hostUnusual = Key('ai_connection_host_unusual');
  static const keyPaste = Key('ai_connection_key_paste');
  static const keyInfo = Key('ai_connection_key_info');
  static const models = Key('ai_connection_models');
  static const guide = Key('ai_connection_guide');
  static const detailHelp = Key('ai_connection_detail_help');
  static const imported = Key('ai_connection_imported');
  static const demoLocked = Key('ai_connection_demo_locked');
  static const preview = Key('ai_connection_preview');
  static const photos = Key('ai_connection_photos');

  static Key detail(AiDetailLevel level) =>
      Key('ai_connection_detail_${level.name}');

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

String? aiPresetNote(AppLocalizations l10n, AiProviderPreset preset) =>
    switch (preset) {
      AiProviderPreset.openAi => l10n.aiNoteOpenAi,
      AiProviderPreset.openRouter => l10n.aiNoteOpenRouter,
      AiProviderPreset.gemini => l10n.aiNoteGemini,
      AiProviderPreset.anthropic => l10n.aiNoteAnthropic,
      _ => null,
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

bool _testable(AiConfig config) =>
    config.normalizedUrl != null &&
    config.trimmedModel.isNotEmpty &&
    (!config.preset.keyRequired || config.keyLastFour != null);

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
  var _demo = false;
  var _testing = false;
  var _photos = false;

  bool get _locked => _busy || _demo;

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
    _demo = ref.watch(demoModeProvider);
    final on = ref.watch(aiEnabledProvider);
    _photos = on && ref.watch(foodEnabledProvider);
    return AppPage(
      title: l10n.aiConnectionTitle,
      subtitle: l10n.aiConnectionLead,
      children: on ? _body(l10n, config) : const [],
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
    final note = aiPresetNote(l10n, _preset);
    final modelsTarget = _modelsTarget(config, url);
    return [
      if (_demo) ...[
        _notice(
          Icons.info_outline_rounded,
          l10n.aiDemoLocked,
          AiConnectionKeys.demoLocked,
        ),
        const SizedBox(height: 16),
      ],
      TileGroup(
        children: [
          SettingsTile(
            key: AiConnectionKeys.guide,
            title: l10n.aiGuideTitle,
            leading: const Icon(Icons.menu_book_rounded),
            chevron: true,
            onTap: () => unawaited(context.push(AppPaths.settingsAiGuide)),
          ),
          SettingsTile(
            key: AiConnectionKeys.service,
            title: l10n.aiConnectionService,
            value: aiPresetLabel(l10n, _preset),
            chevron: true,
            onTap: _locked ? null : () => unawaited(_pickPreset(config)),
          ),
        ],
      ),
      if (note != null) ...[
        const SizedBox(height: 6),
        CaptionText(key: AiConnectionKeys.presetNote, note),
      ],
      const SizedBox(height: 16),
      ..._addressField(l10n, url),
      const SizedBox(height: 16),
      ..._keyField(l10n, config, url),
      const SizedBox(height: 16),
      TextField(
        key: AiConnectionKeys.model,
        controller: _model,
        enabled: !_locked,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: l10n.aiConnectionModel,
          suffixIcon: IconButton(
            key: AiConnectionKeys.models,
            tooltip: l10n.aiModelsSearch,
            icon: const Icon(Icons.list_rounded),
            onPressed: modelsTarget == null
                ? null
                : () => unawaited(_pickModel(config, modelsTarget)),
          ),
        ),
      ),
      ..._privacyControls(l10n, config),
      const SizedBox(height: 16),
      AiAdvancedSection(config: config, locked: _locked),
      const SizedBox(height: 24),
      FilledButton(
        key: AiConnectionKeys.save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _canSave(config, url)
            ? () => unawaited(_save(config))
            : null,
        child: Text(l10n.workoutSave),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        key: AiConnectionKeys.test,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: !_locked && _formComplete(config, url)
            ? () => unawaited(_test(config))
            : null,
        child: Text(l10n.aiTestButton),
      ),
      const SizedBox(height: 6),
      _testCaption(l10n, config, url),
      if (config.isTestedForCurrentTarget) ...[
        const SizedBox(height: 16),
        TileGroup(
          children: [
            SettingsTile(
              key: AiConnectionKeys.preview,
              title: l10n.aiPreviewTitle,
              leading: const Icon(Icons.visibility_outlined),
              chevron: true,
              onTap: () => unawaited(context.push(AppPaths.settingsAiPreview)),
            ),
            if (_photos)
              SettingsTile(
                key: AiConnectionKeys.photos,
                title: l10n.aiPhotosTitle,
                detail: l10n.aiPhotosTile,
                leading: const Icon(Icons.photo_camera_outlined),
                chevron: true,
                onTap: () => unawaited(context.push(AppPaths.settingsAiPhotos)),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _privacyControls(AppLocalizations l10n, AiConfig config) {
    final colors = AppColors.of(context);
    return [
      SectionHeader(l10n.aiDetailTitle),
      ChoiceRow<AiDetailLevel>(
        values: AiDetailLevel.values,
        selected: config.detailLevel,
        label: (level) => l10n.aiDetailLevel(level.name),
        keyOf: AiConnectionKeys.detail,
        onSelected: _locked
            ? null
            : (level) => unawaited(
                _saveSetting((c) => c.copyWith(detailLevel: level)),
              ),
      ),
      const SizedBox(height: 6),
      CaptionText(
        key: AiConnectionKeys.detailHelp,
        l10n.aiDetailHelp(config.detailLevel.name),
      ),
      const SizedBox(height: 16),
      MetricCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: SwitchListTile(
          key: AiConnectionKeys.imported,
          value: config.importedIncluded,
          onChanged: _locked
              ? null
              : (on) => unawaited(
                  _saveSetting((c) => c.copyWith(importedIncluded: on)),
                ),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.aiImportedTitle),
          subtitle: CaptionText(l10n.aiImportedBody),
          activeThumbColor: colors.background,
          activeTrackColor: colors.textPrimary,
          inactiveThumbColor: colors.textSecondary,
          inactiveTrackColor: colors.surfaceInner,
        ),
      ),
    ];
  }

  Future<void> _saveSetting(AiConfig Function(AiConfig) change) =>
      ref.read(aiConfigProvider.notifier).edit(change);

  Widget _notice(IconData icon, String text, Key key) => Row(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.of(context).heart),
      const SizedBox(width: 8),
      Expanded(child: BodyText(text)),
    ],
  );

  AiConfig? _modelsTarget(AiConfig config, NormalizedBaseUrl? url) {
    if (_locked || url == null) return null;
    return config.copyWith(
      preset: _preset,
      baseUrl: _url.text.trim(),
      model: _model.text.trim(),
    );
  }

  Future<void> _pickModel(AiConfig config, AiConfig target) async {
    final typed = _key.text.trim();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiModelsSheet(
        config: target,
        storedKeyAllowed:
            config.hostKey != null && target.hostKey == config.hostKey,
        typedKey: typed.isEmpty ? null : typed,
      ),
    );
    if (!mounted || picked == null) return;
    _model.text = picked;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted || text.isEmpty) return;
    _key.text = text;
  }

  Widget _keyInfoButton(AppLocalizations l10n) => IconButton(
    key: AiConnectionKeys.keyInfo,
    tooltip: l10n.aiKeyInfoTitle,
    icon: const Icon(Icons.info_outline_rounded),
    onPressed: () => unawaited(context.push(AppPaths.settingsAiKeyInfo)),
  );

  bool _formComplete(AiConfig config, NormalizedBaseUrl? url) =>
      url != null &&
      _model.text.trim().isNotEmpty &&
      (!_preset.keyRequired ||
          _key.text.trim().isNotEmpty ||
          config.keyLastFour != null);

  Widget _testCaption(
    AppLocalizations l10n,
    AiConfig config,
    NormalizedBaseUrl? url,
  ) {
    final profile = ref.watch(aiTestedProfileProvider).value;
    final at = config.testedAtUtcMs;
    if (!_formComplete(config, url)) {
      return CaptionText(
        key: AiConnectionKeys.testFillFirst,
        l10n.aiTestFillFirst,
      );
    }
    if (profile == null || at == null) return const SizedBox.shrink();
    final when = MetricFormat.of(context).clockOrDay(
      DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      ref.read(clockProvider)(),
    );
    return CaptionText(
      key: AiConnectionKeys.tested,
      l10n.aiTestTested(when, profile.jsonMode.name),
    );
  }

  /// Saves pending edits first, so the test always runs on the stored target.
  Future<void> _test(AiConfig config) async {
    if (_testing) return;
    _testing = true;
    try {
      if (_canSave(config, _parsedUrl(_url.text))) await _save(config);
      final saved = await ref.read(aiConfigProvider.future);
      final pending = _canSave(saved, _parsedUrl(_url.text));
      if (!mounted || pending || !_testable(saved)) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => AiTestConnectionSheet(config: saved),
      );
    } finally {
      _testing = false;
    }
  }

  List<Widget> _addressField(AppLocalizations l10n, NormalizedBaseUrl? url) {
    final cleartext = url?.isCleartext ?? false;
    final hint = _preset.placeholderUrl;
    return [
      TextField(
        key: AiConnectionKeys.address,
        controller: _url,
        enabled: !_locked,
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
      if (url?.hasNonAsciiHost ?? false) ...[
        const SizedBox(height: 8),
        _notice(
          Icons.warning_amber_rounded,
          l10n.aiHostUnusual,
          AiConnectionKeys.hostUnusual,
        ),
      ],
      if (cleartext) ...[
        const SizedBox(height: 8),
        _notice(
          Icons.lock_open_rounded,
          l10n.aiConnectionNotEncrypted,
          AiConnectionKeys.notEncrypted,
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
          enabled: !_locked,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.key_rounded),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: AiConnectionKeys.keyPaste,
                  tooltip: l10n.aiKeyPaste,
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _locked ? null : () => unawaited(_paste()),
                ),
                _keyInfoButton(l10n),
              ],
            ),
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
          Flexible(
            child: TextButton(
              key: AiConnectionKeys.keyReplace,
              onPressed: _locked
                  ? null
                  : () => setState(() => _replacingKey = true),
              child: Text(l10n.aiConnectionKeyReplace),
            ),
          ),
          _keyInfoButton(l10n),
        ],
      ),
    );
  }

  bool _canSave(AiConfig config, NormalizedBaseUrl? url) {
    if (_locked || url == null) return false;
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
    if (moves) await _persist();
  }

  Future<void> _save(AiConfig config) async {
    if (_hostMoves(config, _url.text) && !await _confirmSwitch(config)) {
      return;
    }
    await _persist();
  }

  Future<bool> _confirmSwitch(AiConfig config) async {
    final host = config.normalizedUrl?.asciiHost ?? config.baseUrl;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => _switchDialog(dialogCtx, host),
    );
    return mounted && ok == true;
  }

  Future<void> _persist() async {
    setState(() => _busy = true);
    try {
      final controller = ref.read(aiConfigProvider.notifier);
      final baseUrl = _url.text.trim();
      final model = _model.text.trim();
      await controller.edit(
        (current) =>
            _withPresetDefaults(current)
                .copyWith(baseUrl: baseUrl, model: model),
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
