import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ring/application/auto_measurements_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/presentation/ring_cards.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';
import 'package:ring_driver/ring_driver.dart';

const _spo2Every = Duration(hours: 1);
const _slotEvery = Duration(minutes: 30);

class AutoMeasurementsCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measurements = ref.watch(autoMeasurementsProvider).value;
    if (measurements == null) return const SizedBox.shrink();
    final capabilities = ref.watch(smartRingDriverProvider).capabilities;
    final shown = [
      if (capabilities.contains(RingCapability.heartRateInterval))
        AutoMeasurement.heartRate,
      if (capabilities.contains(RingCapability.autoMonitors)) ...[
        AutoMeasurement.spo2,
        AutoMeasurement.hrv,
        AutoMeasurement.stress,
      ],
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final l10n = MetricFormat.of(context).l10n;
    final notifier = ref.read(autoMeasurementsProvider.notifier);
    final card = MetricCard(
      key: RingKeys.measurements,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.ringAutoTitle,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          for (final measurement in shown)
            _MeasurementRow(
              measurement: measurement,
              on: measurements.isOn(measurement),
              onChanged: (on) => unawaited(notifier.turn(measurement, on: on)),
            ),
          const SizedBox(height: 4),
          CaptionText(l10n.ringAutoNote),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: cardGap),
      child: card,
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const new({
    required this.measurement,
    required this.on,
    required this.onChanged,
  });

  final AutoMeasurement measurement;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.surfaceBorder)),
      ),
      child: SwitchListTile(
        key: RingKeys.measurement(measurement),
        value: on,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
        title: Text(_name(l10n), style: theme.textTheme.bodyMedium),
        subtitle: CaptionText(_detail(format)),
        activeThumbColor: colors.background,
        activeTrackColor: colors.activity,
        inactiveThumbColor: colors.textSecondary,
        inactiveTrackColor: colors.surfaceInner,
      ),
    );
  }

  String _name(AppLocalizations l10n) => switch (measurement) {
    AutoMeasurement.heartRate => l10n.ringAutoHeartRate,
    AutoMeasurement.spo2 => l10n.ringAutoSpo2,
    AutoMeasurement.stress => l10n.ringAutoStress,
    AutoMeasurement.hrv => l10n.ringAutoHrv,
  };

  String _detail(MetricFormat format) {
    final l10n = format.l10n;
    if (on) return l10n.ringAutoEvery(format.duration(_every));
    if (measurement == AutoMeasurement.heartRate) {
      return l10n.ringAutoHeartRateOff;
    }
    return l10n.ringAutoOff;
  }

  Duration get _every => switch (measurement) {
    AutoMeasurement.heartRate => SyncRing.defaultHeartRateInterval,
    AutoMeasurement.spo2 => _spo2Every,
    AutoMeasurement.stress || AutoMeasurement.hrv => _slotEvery,
  };
}
