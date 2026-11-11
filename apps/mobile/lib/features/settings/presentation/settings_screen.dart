import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/presentation/health_status_screen.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/presentation/about_section.dart';
import 'package:open_ring/features/settings/presentation/delete_data_tile.dart';
import 'package:open_ring/features/settings/presentation/language_section.dart';
import 'package:open_ring/features/settings/presentation/notifications_section.dart';
import 'package:open_ring/features/settings/presentation/profile_section.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  static const healthKey = Key('settings_health');
  static const exportKey = Key('settings_export');
  static const sourcesKey = Key('settings_sources');
  static const widgetsKey = Key('settings_widgets');

  static Key themeModeKey(ThemeMode mode) => Key('theme_mode_${mode.name}');

  static Key unitKey(UnitSystem units) => Key('settings_units_${units.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final units = ref.watch(unitSystemProvider).value ?? UnitSystem.metric;
    return AppPage(
      title: l10n.settingsTitle,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.settingsAppearance,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        TileGroup(
          children: [
            RadioGroup<ThemeMode>(
              groupValue: ref.watch(themeModeProvider),
              onChanged: (mode) => _selectTheme(ref, mode),
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      key: themeModeKey(mode),
                      value: mode,
                      contentPadding: EdgeInsets.zero,
                      title: Text(mode.label(l10n)),
                      subtitle: mode == ThemeMode.system
                          ? CaptionText(_systemThemeNow(context, l10n))
                          : null,
                    ),
                ],
              ),
            ),
            SettingsTile(
              title: l10n.settingsTextSize,
              detail: l10n.settingsTextSizeNote,
              value: l10n.settingsTextSizeValue,
            ),
          ],
        ),
        SectionHeader(l10n.settingsProfile),
        const ProfileSection(),
        const SizedBox(height: 8),
        CaptionText(l10n.settingsProfileNote),
        SectionHeader(l10n.settingsUnits),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsMeasurements,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
              ChoiceRow<UnitSystem>(
                values: UnitSystem.values,
                selected: units,
                keyOf: unitKey,
                label: (value) => value.label(l10n),
                onSelected: (value) => unawaited(
                  ref.read(unitSystemProvider.notifier).select(value),
                ),
              ),
            ],
          ),
        ),
        const LanguageSection(),
        const NotificationsSection(),
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          SectionHeader(l10n.settingsHomeScreen),
          TileGroup(
            children: [
              SettingsTile(
                key: widgetsKey,
                leading: Icon(Icons.widgets_rounded, color: colors.activity),
                title: l10n.widgetsTitle,
                detail: l10n.widgetSettingsDetail,
                chevron: true,
                onTap: () => context.go(AppPaths.settingsWidgets),
              ),
            ],
          ),
        ],
        SectionHeader(l10n.settingsData),
        TileGroup(
          children: [
            SettingsTile(
              key: healthKey,
              leading: Icon(Icons.favorite_rounded, color: colors.heart),
              title: healthPlatformName(),
              detail: healthLinkDetail(
                MetricFormat.of(context),
                ref.watch(healthStatusProvider).value,
              ),
              chevron: true,
              onTap: () => context.go(AppPaths.settingsHealth),
            ),
            SettingsTile(
              key: exportKey,
              leading: Icon(Icons.ios_share_rounded, color: colors.oxygen),
              title: l10n.exportTitle,
              detail: l10n.settingsExportDetail,
              chevron: true,
              onTap: () => context.go(AppPaths.settingsExport),
            ),
            SettingsTile(
              key: sourcesKey,
              leading: Icon(Icons.hub_rounded, color: colors.sleep),
              title: l10n.sourcesTitle,
              detail: l10n.settingsSourcesDetail,
              chevron: true,
              onTap: () => context.go(AppPaths.settingsSources),
            ),
            const DeleteDataTile(),
          ],
        ),
        SectionHeader(l10n.settingsAbout),
        const AboutSection(),
      ],
    );
  }

  String _systemThemeNow(BuildContext context, AppLocalizations l10n) =>
      switch (MediaQuery.platformBrightnessOf(context)) {
        Brightness.dark => l10n.themeModeNowDark,
        Brightness.light => l10n.themeModeNowLight,
      };

  void _selectTheme(WidgetRef ref, ThemeMode? mode) {
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

extension on UnitSystem {
  String label(AppLocalizations l10n) => switch (this) {
    UnitSystem.metric => l10n.settingsMetric,
    UnitSystem.imperial => l10n.settingsImperial,
  };
}
