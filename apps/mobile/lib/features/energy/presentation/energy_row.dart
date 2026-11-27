import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class EnergyRowKeys {
  static const row = Key('today_energy_row');
  static const note = Key('today_energy_row_note');
  static const range = Key('today_energy_row_range');
  static const unit = Key('today_energy_row_unit');
}

String _missingLine(AppLocalizations l10n, List<EnergyField> fields) {
  if (fields.length != 1) return l10n.energyRowMissingSeveral;
  return switch (fields.single) {
    EnergyField.birthYear => l10n.energyRowMissingAge,
    EnergyField.height => l10n.energyRowMissingHeight,
    EnergyField.weight => l10n.energyRowMissingWeight,
    EnergyField.sex => l10n.energyRowMissingSex,
  };
}

class EnergyRowSlot extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<EnergyRowSlot> createState() => _EnergyRowSlotState();
}

class _EnergyRowSlotState extends ConsumerState<EnergyRowSlot> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(energyAsOfProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(energyGateProvider) != EnergyGate.on) {
      return const SizedBox.shrink();
    }
    return const EnergyRow();
  }
}

class EnergyRow extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ref.watch(energyNowProvider);
    final computed = row.value;
    if (row.hasError || computed == null) return const SizedBox.shrink();
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    switch (computed.day) {
      case EnergyDayUnderage():
        return const SizedBox.shrink();
      case EnergyDayMissing(:final fields):
        return _EnergyCard(
          note: _missingLine(l10n, fields.toList()),
          onTap: () => context.go(AppPaths.settings),
        );
      case EnergyDayEstimate(:final range) when range.low < energyRowFloor:
        return _EnergyCard(
          note: l10n.energyRowStarting,
          onTap: () => context.go(AppPaths.energy),
        );
      case EnergyDayEstimate(:final range):
        final asOf = computed.asOf;
        final low = format.integer(range.low);
        final high = format.integer(range.high);
        void open() => context.go(AppPaths.energy);
        return Semantics(
          container: true,
          excludeSemantics: true,
          button: true,
          onTap: open,
          label: l10n.energyRowSemantics(low, high),
          child: _EnergyCard(
            note: l10n.energyRowSoFar(format.clock(asOf, asOf.timeZoneOffset)),
            range: l10n.energyRowRange(low, high),
            onTap: open,
          ),
        );
    }
  }
}

class _EnergyCard extends StatelessWidget {
  const new({required this.note, this.range, this.onTap});

  final String note;
  final String? range;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final range = this.range;
    return Padding(
      padding: const EdgeInsets.only(bottom: cardGap),
      child: MetricCard(
        key: EnergyRowKeys.row,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // A Wrap and not a Row: at a large text scale the range drops under
        // the title instead of squeezing it.
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.energyTitle,
                  style: theme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                CaptionText(note, key: EnergyRowKeys.note),
              ],
            ),
            if (range != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    range,
                    key: EnergyRowKeys.range,
                    style: theme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  CaptionText(l10n.energyRowUnit, key: EnergyRowKeys.unit),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
