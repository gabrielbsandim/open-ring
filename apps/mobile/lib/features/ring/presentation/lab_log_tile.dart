import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/ring/domain/frame_insight.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:open_ring/features/ring/domain/hex_bytes.dart';
import 'package:open_ring/features/ring/presentation/lab_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class LabLogTile extends StatelessWidget {
  const new({required this.entry, super.key});

  final FrameLogEntry entry;

  static String clock(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final millis = local.millisecond.toString().padLeft(3, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.$millis';
  }

  static String shortCharacteristic(String uuid) => uuid.split('-').first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final accent = switch (entry.direction) {
      FrameDirection.tx => colors.oxygen,
      FrameDirection.rx => colors.activity,
    };
    final insight = FrameInsight.of(entry);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  entry.direction.label(l10n),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  clock(entry.at),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.textLabel,
                  ),
                ),
                Text(
                  shortCharacteristic(entry.characteristic),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.textLabel,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              HexBytes.spaced(entry.bytes),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
            if (insight != null)
              for (final line in insight.lines(l10n))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    line,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
