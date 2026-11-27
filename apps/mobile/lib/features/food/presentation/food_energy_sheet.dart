import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';

abstract final class FoodEnergySheetKeys {
  static const sheet = Key('food_energy_sheet');
  static const cancel = Key('food_energy_sheet_cancel');
  static const on = Key('food_energy_sheet_on');
}

/// True once the opt in is stored.
Future<bool> showFoodEnergyOptInSheet(
  BuildContext context, {
  required LocalDate screenedOn,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).surface,
      builder: (_) => FoodEnergyOptInSheet(screenedOn: screenedOn),
    ) ??
    false;

class FoodEnergyOptInSheet extends ConsumerStatefulWidget {
  const new({required this.screenedOn, super.key});

  final LocalDate screenedOn;

  @override
  ConsumerState<FoodEnergyOptInSheet> createState() =>
      _FoodEnergyOptInSheetState();
}

class _FoodEnergyOptInSheetState extends ConsumerState<FoodEnergyOptInSheet> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final f = MetricFormat.of(context);
    final l = f.l10n;
    return SafeArea(
      key: FoodEnergySheetKeys.sheet,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.foodEnergySheetTitle,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            BodyText(l.foodEnergySheetScreened(f.date(widget.screenedOn))),
            const SizedBox(height: 8),
            BodyText(l.foodEnergySheetPoints),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: FoodEnergySheetKeys.cancel,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l.settingsDeleteCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: FoodEnergySheetKeys.on,
                    onPressed: _busy ? null : () => unawaited(_turnOn()),
                    child: Text(l.foodEnergySheetOn),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _turnOn() async {
    // A second tap can land before the rebuild that disables the button.
    if (_busy) return;
    setState(() => _busy = true);
    final on = await ref
        .read(foodEnergyOptInControllerProvider.notifier)
        .turnOn()
        .catchError((Object _) => false);
    if (!mounted) return;
    if (!on) return setState(() => _busy = false);
    Navigator.of(context).pop(true);
  }
}
