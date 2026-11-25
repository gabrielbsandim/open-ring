import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/food/application/food_energy.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/presentation/food_energy_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class FoodEnergyKeys {
  static const blocked = Key('food_energy_blocked');
  static const blockedAction = Key('food_energy_blocked_action');
  static const screenFirst = Key('food_energy_screen_first');
  static const answer = Key('food_energy_answer');
  static const offCard = Key('food_energy_off_card');
  static const turnOn = Key('food_energy_turn_on');
  static const first = Key('food_energy_first');
  static const never = Key('food_energy_never');
  static const building = Key('food_energy_building');
  static const toggle = Key('food_energy_switch');

  static Key need(FoodEnergyNeed need) => Key('food_energy_need_${need.name}');
}

/// The rows the off and building states list; `days` is the select's other.
enum FoodEnergyNeed { ai, body, screening, weighIns, days }

class FoodEnergyScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = MetricFormat.of(context).l10n;
    final view = ref.watch(foodEnergyProvider);
    final gate = view.value?.gate;
    if (gate is FoodEnergyHidden) {
      return AppPage(title: l.foodEnergyTitle, children: const []);
    }
    return AppPage(
      title: l.foodEnergyTitle,
      subtitle: l.foodEnergyLead,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _body(context, ref, view, l),
        ),
      ],
    );
  }

  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<FoodEnergyView> view,
    AppLocalizations l,
  ) {
    if (view.hasError && !view.hasValue) return [BodyText(l.metricLoadError)];
    final value = view.value;
    if (value == null) return const [SizedBox(height: 96)];
    final counts = value.result?.counts;
    return switch (value.gate) {
      FoodEnergyHidden() => const [],
      FoodEnergyDemo() => [_never(l)],
      FoodEnergyBlocked(:final block) => _blocked(context, block, l),
      FoodEnergyNeedsScreening() => [
        MetricCard(
          key: FoodEnergyKeys.screenFirst,
          child: BodyText(l.foodEnergyScreenFirst),
        ),
        const SizedBox(height: 16),
        ActionButton(
          buttonKey: FoodEnergyKeys.answer,
          label: l.foodEnergyAnswer,
          onPressed: () => _push(context, AppPaths.goalsScreeningForEnergy),
        ),
      ],
      FoodEnergyOffered(:final screenedOn) => [
        MetricCard(
          key: FoodEnergyKeys.offCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccentTitle(
                title: l.foodEnergyOffTitle,
                accent: AppColors.of(context).activity,
              ),
              const SizedBox(height: 8),
              BodyText(l.foodEnergyOffBody),
              const SizedBox(height: 8),
              ..._needs(context, counts, l),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ActionButton(
          buttonKey: FoodEnergyKeys.turnOn,
          label: l.foodEnergyTurnOn,
          onPressed: () => unawaited(_turnOn(context, screenedOn)),
        ),
        const SizedBox(height: 12),
        CaptionText(l.foodEnergyFirst, key: FoodEnergyKeys.first),
        const SizedBox(height: 8),
        _never(l),
      ],
      FoodEnergyOn() => [
        if (value.result case FoodEnergyHold(last: null)) ...[
          MetricCard(
            key: FoodEnergyKeys.building,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _needs(context, counts, l),
            ),
          ),
          const SizedBox(height: 12),
          CaptionText(l.foodEnergyFirst, key: FoodEnergyKeys.first),
          const SizedBox(height: 16),
        ],
        const FoodEnergySwitch(),
      ],
    };
  }

  Widget _never(AppLocalizations l) =>
      CaptionText(l.foodEnergyNever, key: FoodEnergyKeys.never);

  List<Widget> _blocked(
    BuildContext context,
    FoodEnergyBlock block,
    AppLocalizations l,
  ) {
    final action = switch (block) {
      FoodEnergyBlock.bodyOff => (
        label: l.goalsSetupOpenBody,
        path: AppPaths.body,
      ),
      FoodEnergyBlock.ageMissing ||
      FoodEnergyBlock.heightMissing ||
      FoodEnergyBlock.sexMissing => (
        label: l.goalsProfileOpen,
        path: AppPaths.settings,
      ),
      _ => null,
    };
    return [
      MetricCard(
        key: FoodEnergyKeys.blocked,
        child: BodyText(l.foodEnergyBlocked(block.name)),
      ),
      if (action != null) ...[
        const SizedBox(height: 16),
        ActionButton(
          buttonKey: FoodEnergyKeys.blockedAction,
          label: action.label,
          onPressed: () => _push(context, action.path),
        ),
      ],
    ];
  }

  List<Widget> _needs(
    BuildContext context,
    FoodEnergyCounts? counts,
    AppLocalizations l,
  ) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final met = Icon(Icons.check_rounded, size: 20, color: c.activity);
    // Without counts (a failed read) the two count rows show no figure.
    Widget? count(int? value, int total) => value == null
        ? null
        : Text(
            l.foodEnergyNeedCount(value, total),
            style: numberStyle(t.bodyMedium),
          );
    final rows = <(FoodEnergyNeed, Widget?)>[
      (FoodEnergyNeed.ai, met),
      (FoodEnergyNeed.body, met),
      (FoodEnergyNeed.screening, met),
      (FoodEnergyNeed.weighIns, count(counts?.weighIns, foodEnergyMinWeighIns)),
      (FoodEnergyNeed.days, count(counts?.days, foodEnergyMinDays)),
    ];
    return [
      for (final (need, trailing) in rows)
        Padding(
          key: FoodEnergyKeys.need(need),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: BodyText(l.foodEnergyNeed(need.name))),
              const SizedBox(width: 8),
              ?trailing,
            ],
          ),
        ),
    ];
  }

  void _push(BuildContext context, String path) {
    final router = GoRouter.maybeOf(context);
    if (router != null) unawaited(router.push(path));
  }

  Future<void> _turnOn(BuildContext context, LocalDate screenedOn) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final on = await showFoodEnergyOptInSheet(context, screenedOn: screenedOn);
    if (!on) return;
    messenger.showSnackBar(SnackBar(content: Text(l.foodEnergyOnDone)));
  }
}

/// Turns Weekly energy off at once; the checked items stay stored.
class FoodEnergySwitch extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return SwitchListTile(
      key: FoodEnergyKeys.toggle,
      contentPadding: EdgeInsets.zero,
      value: true,
      onChanged: (_) => unawaited(_off(context, ref, l)),
      title: Text(l.foodEnergyTitle),
      subtitle: Text(l.foodEnergySwitch),
    );
  }

  Future<void> _off(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(foodEnergyOptInControllerProvider.notifier).turnOff();
    messenger.showSnackBar(SnackBar(content: Text(l.foodEnergyOffDone)));
  }
}
