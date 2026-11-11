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
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/presentation/health_status_screen.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/presentation/about_section.dart';
import 'package:open_ring/features/settings/presentation/delete_data_tile.dart';
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
    return AppPage(
      title: l10n.settingsTitle,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.settingsProfile,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        const ProfileSection(),
        SectionHeader(l10n.settingsGeneral),
        TileGroup(
          children: [
            _ChoiceTile<UnitSystem>(
              title: l10n.settingsUnits,
              values: UnitSystem.values,
              selected:
                  ref.watch(unitSystemProvider).value ?? UnitSystem.metric,
              keyOf: unitKey,
              label: (value) => value.label(l10n),
              onSelected: (value) => unawaited(
                ref.read(unitSystemProvider.notifier).select(value),
              ),
            ),
            _ChoiceTile<ThemeMode>(
              title: l10n.settingsAppearance,
              values: ThemeMode.values,
              selected: ref.watch(themeModeProvider),
              keyOf: themeModeKey,
              label: (mode) => mode.label(l10n),
              onSelected: (mode) => _selectTheme(ref, mode),
            ),
            if (defaultTargetPlatform == TargetPlatform.android)
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
        const NotificationsSection(),
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
              key: sourcesKey,
              leading: Icon(Icons.hub_rounded, color: colors.sleep),
              title: l10n.sourcesTitle,
              detail: l10n.settingsSourcesDetail,
              chevron: true,
              onTap: () => context.go(AppPaths.settingsSources),
            ),
            SettingsTile(
              key: exportKey,
              leading: Icon(Icons.ios_share_rounded, color: colors.oxygen),
              title: l10n.exportTitle,
              detail: l10n.settingsExportDetail,
              chevron: true,
              onTap: () => context.go(AppPaths.settingsExport),
            ),
            const DeleteDataTile(),
          ],
        ),
        SectionHeader(l10n.settingsAbout),
        const AboutSection(),
      ],
    );
  }

  void _selectTheme(WidgetRef ref, ThemeMode mode) =>
      unawaited(ref.read(themeModeProvider.notifier).select(mode));
}

class _ChoiceTile<T> extends StatelessWidget {
  const new({
    required this.title,
    required this.values,
    required this.selected,
    required this.keyOf,
    required this.label,
    required this.onSelected,
  });

  final String title;
  final List<T> values;
  final T selected;
  final Key Function(T value) keyOf;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.of(context).textPrimary),
          ),
          const SizedBox(height: 8),
          ChoiceRow<T>(
            values: values,
            selected: selected,
            keyOf: keyOf,
            label: label,
            onSelected: onSelected,
          ),
        ],
      ),
    );
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
