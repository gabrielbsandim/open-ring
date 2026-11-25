import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/presentation/ai_models_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_vision_test_card.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/presentation/meal_photo_pause_card.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiPhotoKeys {
  static const demoLocked = Key('ai_photos_demo_locked');
  static const vision = Key('ai_photos_vision');
  static const model = Key('ai_photos_model');
  static const modelClear = Key('ai_photos_model_clear');
  static const limit = Key('ai_photos_limit');
  static const limitLess = Key('ai_photos_limit_less');
  static const limitMore = Key('ai_photos_limit_more');
  static const consent = Key('ai_photos_consent');
  static const withdraw = Key('ai_photos_withdraw');
  static const sends = Key('ai_photos_sends');
}

class AiPhotoSettingsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AiPhotoSettingsScreen> createState() =>
      _AiPhotoSettingsScreenState();
}

class _AiPhotoSettingsScreenState extends ConsumerState<AiPhotoSettingsScreen> {
  var _testOpen = false;
  var _demo = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(aiEnabledProvider) && ref.watch(foodEnabledProvider);
    final config = ref.watch(aiConfigProvider).value;
    _demo = ref.watch(demoModeProvider);
    return AppPage(
      title: l10n.aiPhotosTitle,
      subtitle: l10n.aiPhotosLead,
      children: on && config != null ? _body(l10n, config) : const [],
    );
  }

  List<Widget> _body(AppLocalizations l10n, AiConfig config) => [
    if (_demo) ...[
      _note(
        Icons.info_outline_rounded,
        l10n.aiDemoLocked,
        AiPhotoKeys.demoLocked,
      ),
      const SizedBox(height: 16),
    ],
    MealPhotoPauseCard(
      locked: _demo || _testOpen,
      onTest: () => setState(() => _testOpen = true),
    ),
    if (_testOpen) ...[
      AiVisionTestCard(config: config, locked: _demo),
      const SizedBox(height: 16),
    ],
    TileGroup(
      children: [
        _visionTile(l10n, config),
        _modelTile(l10n, config),
        _limitTile(l10n, config),
        _consentTile(l10n, config),
      ],
    ),
    const SizedBox(height: 16),
    _note(Icons.info_outline_rounded, l10n.aiPhotosSends, AiPhotoKeys.sends),
  ];

  Widget _visionTile(AppLocalizations l10n, AiConfig config) {
    final vision = ref.watch(aiPhotoVisionProvider).value;
    final state = (vision ?? AiVisionSupport.unknown).name;
    return SettingsTile(
      key: AiPhotoKeys.vision,
      title: l10n.aiPhotosVisionTitle,
      detail: l10n.aiPhotosVisionState(state, aiPhotoTarget(config)),
      leading: const Icon(Icons.image_outlined),
      chevron: true,
      onTap: _demo || _testOpen ? null : () => setState(() => _testOpen = true),
    );
  }

  Widget _modelTile(AppLocalizations l10n, AiConfig config) {
    final photo = config.photoModel;
    return SettingsTile(
      key: AiPhotoKeys.model,
      title: l10n.aiPhotosModelTitle,
      detail: photo == null ? l10n.aiPhotosModelSame : null,
      value: photo,
      leading: const Icon(Icons.chat_bubble_outline_rounded),
      trailing: photo == null
          ? null
          : TextButton(
              key: AiPhotoKeys.modelClear,
              onPressed: _demo
                  ? null
                  : () => unawaited(
                      _edit((c) => c.copyWith(clearPhotoModel: true)),
                    ),
              child: Text(l10n.aiPhotosModelClear),
            ),
      chevron: true,
      onTap: _demo ? null : () => unawaited(_pickModel(config)),
    );
  }

  Widget _limitTile(AppLocalizations l10n, AiConfig config) {
    final limit = config.photoDailyLimit;
    return SettingsTile(
      key: AiPhotoKeys.limit,
      title: l10n.aiPhotosLimitTitle,
      detail: l10n.aiPhotosLimitValue(limit),
      leading: const Icon(Icons.speed_rounded),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            key: AiPhotoKeys.limitLess,
            tooltip: l10n.bodySheetDecrease('1'),
            onPressed: _demo || limit <= aiMinPhotoDailyLimit
                ? null
                : () => unawaited(_step(-1)),
            icon: const Icon(Icons.remove_rounded),
          ),
          IconButton.outlined(
            key: AiPhotoKeys.limitMore,
            tooltip: l10n.bodySheetIncrease('1'),
            onPressed: _demo || limit >= aiMaxPhotoDailyLimit
                ? null
                : () => unawaited(_step(1)),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  Widget _consentTile(AppLocalizations l10n, AiConfig config) {
    final consent = ref.watch(aiMealPhotoConsentProvider).value;
    final host = config.hostKey;
    final given =
        consent != null &&
        host != null &&
        consent.covers(
          hostKey: host,
          policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        );
    final date = MaterialLocalizations.of(context).formatMediumDate(
      DateTime.fromMillisecondsSinceEpoch(consent?.consentedAtUtcMs ?? 0),
    );
    final name = config.normalizedUrl?.asciiHost ?? config.baseUrl;
    return SettingsTile(
      key: AiPhotoKeys.consent,
      title: l10n.aiPhotosConsentTitle,
      detail: given
          ? l10n.aiConsentGiven(name, date)
          : l10n.aiPhotosConsentNone,
      leading: const Icon(Icons.send_outlined),
      trailing: given
          ? TextButton(
              key: AiPhotoKeys.withdraw,
              onPressed: _demo ? null : () => unawaited(_withdraw(l10n)),
              child: Text(l10n.aiConsentWithdraw),
            )
          : null,
    );
  }

  Widget _note(IconData icon, String text, Key key) => Row(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.of(context).textLabel),
      const SizedBox(width: 8),
      Expanded(child: CaptionText(text)),
    ],
  );

  Future<void> _edit(AiConfig Function(AiConfig) change) =>
      ref.read(aiConfigProvider.notifier).edit(change);

  Future<void> _step(int delta) => _edit(
    (c) => c.copyWith(
      photoDailyLimit: (c.photoDailyLimit + delta).clamp(
        aiMinPhotoDailyLimit,
        aiMaxPhotoDailyLimit,
      ),
    ),
  );

  Future<void> _pickModel(AiConfig config) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiModelsSheet(config: config, storedKeyAllowed: true),
    );
    if (!mounted || picked == null) return;
    await _edit(
      (c) => c.copyWith(
        photoModel: picked,
        clearPhotoModel: picked == c.trimmedModel,
      ),
    );
  }

  Future<void> _withdraw(AppLocalizations l10n) async {
    await ref.read(aiConfigProvider.notifier).withdrawMealPhotoConsent();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.aiPhotosWithdrawn)));
  }
}
