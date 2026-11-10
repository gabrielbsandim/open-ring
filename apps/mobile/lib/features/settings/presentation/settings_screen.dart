import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  static Key themeModeKey(ThemeMode mode) => Key('theme_mode_${mode.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return AppPage(
      title: l10n.settingsTitle,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.settingsAppearance,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<ThemeMode>(
          groupValue: ref.watch(themeModeProvider),
          onChanged: (mode) => _select(ref, mode),
          child: Column(
            children: [
              for (final mode in ThemeMode.values)
                RadioListTile<ThemeMode>(
                  key: themeModeKey(mode),
                  value: mode,
                  contentPadding: EdgeInsets.zero,
                  title: Text(mode.label(l10n)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.settingsEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textLabel),
        ),
      ],
    );
  }

  void _select(WidgetRef ref, ThemeMode? mode) {
    if (mode == null) return;
    unawaited(ref.read(themeModeProvider.notifier).select(mode));
  }
}

extension on ThemeMode {
  String label(AppLocalizations l10n) => switch (this) {
    ThemeMode.system => l10n.themeModeSystem,
    ThemeMode.light => l10n.themeModeLight,
    ThemeMode.dark => l10n.themeModeDark,
  };
}
