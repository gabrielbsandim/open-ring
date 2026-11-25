import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/food_data.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/application/food_photo_storage.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class FoodModuleKeys {
  static const state = Key('food_module_state');
  static const kept = Key('food_module_kept');
  static const stored = Key('food_module_stored');
  static const photos = Key('food_module_photos');
  static const formula = Key('food_module_formula');
  static const delete = Key('food_module_delete');
  static const deleteConfirm = Key('food_module_delete_confirm');
  static const deleteCancel = Key('food_module_delete_cancel');
  static const toggle = Key('food_module_toggle');
  static const aiPhotos = Key('food_module_ai_photos');
  static const aiWithdraw = Key('food_module_ai_withdraw');
  static const energy = Key('food_module_energy');
}

class FoodModuleScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FoodModuleScreen> createState() => _FoodModuleScreenState();
}

class _FoodModuleScreenState extends ConsumerState<FoodModuleScreen> {
  var _deleting = false;
  var _toggling = false;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final on =
        ref.watch(enabledModulesProvider).value?.contains(ModuleId.food) ??
        false;
    final count = ref.watch(foodDataCountProvider);
    final hasData = count.value?.hasData ?? false;
    final toggleAction = _toggling ? null : () => unawaited(_toggle(on: !on));
    final aiOn = ref.watch(aiEnabledProvider);
    final ai = aiOn && on;
    return AppPage(
      title: l10n.foodTitle,
      subtitle: l10n.moduleFoodDetail,
      children: [
        ModuleStatePill(
          key: FoodModuleKeys.state,
          on: on,
          label: on ? l10n.modulesOn : l10n.modulesOff,
        ),
        const SizedBox(height: 16),
        if (!on && hasData) ...[
          MetricCard(
            key: FoodModuleKeys.kept,
            color: colors.surfaceInner,
            child: BodyText(l10n.moduleFoodKept),
          ),
          const SizedBox(height: cardGap),
        ],
        ModuleFactsCard(
          title: l10n.moduleBodyAddsTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.moduleFoodAddsToday(l10n.tabToday),
            l10n.moduleFoodAddsPatterns,
            if (ai) l10n.moduleFoodAddsAi('on'),
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyStoresTitle,
          icon: Icons.smartphone_rounded,
          facts: [
            l10n.moduleFoodStoresMeals,
            if (ai) l10n.moduleFoodStoresAi,
            l10n.moduleBodyStoresLocal,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyNeverTitle,
          icon: Icons.block_rounded,
          facts: [l10n.moduleFoodNeverCalories, l10n.moduleFoodNeverUploads],
        ),
        const SizedBox(height: cardGap),
        if (ai) ...[_aiCard(l10n), const SizedBox(height: cardGap)],
        DayScoreLink(
          key: FoodModuleKeys.photos,
          title: l10n.foodPhotosTitle,
          caption: _photosCaption(format, count),
          path: AppPaths.settingsFoodPhotos,
          push: true,
        ),
        const SizedBox(height: cardGap),
        DayScoreLink(
          key: FoodModuleKeys.formula,
          title: l10n.formulaLink,
          // The formula screen adds its AI cards whenever AI is on.
          caption: aiOn
              ? l10n.moduleFoodFormulaCaptionAi
              : l10n.moduleFoodFormulaCaption,
          path: AppPaths.foodFormula,
          push: true,
        ),
        SectionHeader(l10n.moduleFoodDataTitle),
        BodyText(key: FoodModuleKeys.stored, _storedLine(format, count)),
        if (hasData) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: FoodModuleKeys.delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.heart,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _deleting ? null : () => unawaited(_delete()),
            child: Text(l10n.moduleFoodDelete, textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: 12),
        CaptionText(l10n.moduleBodyFoot),
        const SizedBox(height: 24),
        if (on)
          SecondaryButton(
            key: FoodModuleKeys.toggle,
            label: l10n.moduleFoodTurnOff,
            onPressed: toggleAction,
          ),
        if (!on)
          ActionButton(
            key: FoodModuleKeys.toggle,
            label: l10n.moduleFoodTurnOn,
            onPressed: toggleAction,
          ),
        const SizedBox(height: 8),
        CaptionText(
          on ? l10n.moduleBodyTurnOffNote : l10n.moduleBodyTurnOnNote,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _aiCard(AppLocalizations l10n) {
    final config = ref.watch(aiConfigProvider).value;
    final consent = ref.watch(aiMealPhotoConsentProvider).value;
    final demo = ref.watch(demoModeProvider);
    final host = config?.normalizedUrl?.asciiHost;
    final hostKey = config?.hostKey;
    final at = consent?.consentedAtUtcMs;
    final given =
        at != null &&
        hostKey != null &&
        consent!.covers(
          hostKey: hostKey,
          policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        );
    final consentLine = given
        ? l10n.aiConsentGiven(
            host ?? hostKey,
            MaterialLocalizations.of(context)
                .formatMediumDate(DateTime.fromMillisecondsSinceEpoch(at)),
          )
        : l10n.aiPhotosConsentNone;
    final energy = switch (ref.watch(foodEnergyGateProvider).value) {
      null => null,
      FoodEnergyOn() => l10n.modulesOn,
      FoodEnergyDemo() => l10n.foodEnergySample,
      _ => l10n.foodEnergyTileOff,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TileGroup(
          children: [
            SettingsTile(
              key: FoodModuleKeys.aiPhotos,
              leading: const Icon(Icons.image_outlined),
              title: l10n.foodAiSectionTitle,
              detail: host == null
                  ? l10n.moduleAiConnection('none', '', '')
                  : '${l10n.moduleFoodAiPhotos(host)} $consentLine',
            ),
          ],
        ),
        if (given)
          TextButton(
            key: FoodModuleKeys.aiWithdraw,
            onPressed: demo
                ? null
                : () => unawaited(
                    ref
                        .read(aiConfigProvider.notifier)
                        .withdrawMealPhotoConsent(),
                  ),
            child: Text(l10n.aiConsentWithdraw),
          ),
        const SizedBox(height: cardGap),
        TileGroup(
          children: [
            SettingsTile(
              key: FoodModuleKeys.energy,
              leading: const Icon(Icons.local_fire_department_outlined),
              title: l10n.foodEnergyTitle,
              detail: energy,
              chevron: true,
              onTap: () => unawaited(context.push(AppPaths.foodEnergy)),
            ),
          ],
        ),
      ],
    );
  }

  String _photosCaption(MetricFormat format, AsyncValue<FoodDataCount> count) {
    if (count.hasError) return format.l10n.metricLoadError;
    final value = count.value;
    if (value == null) return '';
    if (value.photos == 0 && value.photoBytes == 0) {
      return format.l10n.foodPhotosCount(0);
    }
    return '${format.l10n.foodPhotosCount(value.photos)} · '
        '${formatPhotoBytes(format, value.photoBytes)}';
  }

  String _storedLine(MetricFormat format, AsyncValue<FoodDataCount> count) {
    if (count.hasError) return format.l10n.metricLoadError;
    final value = count.value;
    if (value == null) return '';
    if (!value.hasData) return format.l10n.moduleFoodDataEmpty;
    return format.l10n.moduleFoodDataCount(
      value.meals,
      value.photos,
      formatPhotoBytes(format, value.photoBytes),
    );
  }

  Future<void> _toggle({required bool on}) async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await setModule(context, ref, OfferedModule.food, on: on);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  // Delete stays disabled until the clear returns so a second tap cannot open
  // a second dialog while the first runs.
  Future<void> _delete() async {
    if (_deleting) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    final deleted = await _confirmAndClear();
    if (mounted) setState(() => _deleting = false);
    if (deleted == null || !mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted ? l10n.moduleFoodDeleted : l10n.moduleFoodDeleteFailed,
          ),
        ),
      );
  }

  Future<bool?> _confirmAndClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteDialog(),
    );
    if (confirmed != true || !mounted) return null;
    return await ref.read(foodDataEraserProvider).clear();
  }
}

class _DeleteDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.moduleFoodDeleteTitle),
      content: Text(l10n.moduleFoodDeleteBody),
      actions: [
        TextButton(
          key: FoodModuleKeys.deleteCancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsDeleteCancel),
        ),
        FilledButton(
          key: FoodModuleKeys.deleteConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.moduleFoodDelete),
        ),
      ],
    );
  }
}
