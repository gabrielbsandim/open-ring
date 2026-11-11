import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class LabDeviceTile extends StatelessWidget {
  const new({required this.device, required this.onConnect, super.key});

  final DiscoveredDevice device;
  final VoidCallback? onConnect;

  static Key keyFor(String id) => Key('lab_device_$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final label = theme.textTheme.bodyMedium?.copyWith(color: colors.textLabel);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: device.looksLikeColmi ? colors.oxygen : colors.surfaceBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.name.isEmpty ? l10n.labUnnamedDevice : device.name,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(device.id, style: label),
            Text(l10n.labSignal(device.rssi), style: label),
            if (device.looksLikeColmi)
              Text(
                l10n.labColmiBadge,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.oxygen,
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: onConnect, child: Text(l10n.labConnect)),
          ],
        ),
      ),
    );
  }
}
