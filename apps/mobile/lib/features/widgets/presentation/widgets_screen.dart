import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';
import 'package:open_ring/features/widgets/presentation/this_week_widget_preview.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_preview.dart';
import 'package:open_ring/features/widgets/presentation/widget_previews.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class WidgetsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const configureKey = Key('widgets_configure_today');
  static const howKey = Key('widgets_how');

  static Key pinKey(HomeWidgetKind kind) => Key('widgets_pin_${kind.name}');

  @override
  ConsumerState<WidgetsScreen> createState() => _WidgetsState();
}

class _WidgetsState extends ConsumerState<WidgetsScreen> {
  HomeWidgetKind? _requested;
  HomeWidgetKind? _failed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(widgetSnapshotProvider).value;
    final now = ref.watch(clockProvider)();
    final config = ref.watch(todayWidgetConfigProvider);
    final modules = ref.watch(activeModulesProvider);
    final hideNumbers = ref.watch(profileWeightHiddenProvider);
    final units = ref.watch(currentUnitSystemProvider);
    final canPin = ref.watch(widgetPinSupportedProvider).value ?? false;
    final effective = TodayWidgetConfig(
      metrics: config.effectiveMetrics(
        enabled: modules,
        hideNumbers: hideNumbers,
      ),
      theme: config.theme,
    );
    final hasEffort = modules.contains(ModuleId.effort);
    final hasGoals = modules.contains(ModuleId.goals);
    return AppPage(
      title: l10n.widgetsTitle,
      children: [
        BodyText(l10n.widgetsIntro),
        SectionHeader(l10n.widgetsAndroid),
        _item(
          context,
          kind: HomeWidgetKind.today,
          title: l10n.widgetTodayName,
          detail: l10n.widgetTodayCatalogDetail(
            effective.metrics.length,
            TodayWidgetConfig.maxMetrics,
          ),
          canPin: canPin && effective.metrics.isNotEmpty,
          child: TodayWidgetPreview(
            config: effective,
            snapshot: snapshot,
            brightness: _previewBrightness(context, config.theme),
            now: now,
            units: units,
          ),
        ),
        const SizedBox(height: 8),
        TileGroup(
          children: [
            SettingsTile(
              key: WidgetsScreen.configureKey,
              title: l10n.widgetConfigureToday,
              detail: l10n.widgetConfigureTodayFieldsDetail,
              chevron: true,
              onTap: () => context.go(AppPaths.settingsWidgetToday),
            ),
          ],
        ),
        if (hasEffort || hasGoals) ...[
          const SizedBox(height: 16),
          _item(
            context,
            kind: HomeWidgetKind.thisWeek,
            title: l10n.goalsWeekTitle,
            detail: _thisWeekDetail(
              l10n,
              hasEffort: hasEffort,
              hasGoals: hasGoals,
            ),
            canPin: canPin,
            child: ThisWeekWidgetPreview(snapshot: snapshot, now: now),
          ),
        ],
        const SizedBox(height: 16),
        _item(
          context,
          kind: HomeWidgetKind.readiness,
          title: l10n.widgetReadinessName,
          detail: l10n.widgetReadinessDetail,
          canPin: canPin,
          child: ReadinessWidgetPreview(snapshot: snapshot, now: now),
        ),
        const SizedBox(height: 16),
        _item(
          context,
          kind: HomeWidgetKind.ring,
          title: l10n.widgetRingName,
          detail: l10n.widgetRingDetail,
          canPin: canPin,
          child: RingWidgetPreview(snapshot: snapshot, now: now),
        ),
        const SizedBox(height: 16),
        _item(
          context,
          kind: HomeWidgetKind.workout,
          title: l10n.widgetWorkoutName,
          detail: l10n.widgetWorkoutDetail,
          canPin: canPin,
          child: WorkoutWidgetPreview(snapshot: snapshot, now: now),
        ),
        SectionHeader(l10n.widgetLockScreenHeading),
        MetricCard(child: BodyText(l10n.widgetLockScreenBody)),
        const SizedBox(height: cardGap),
        TileGroup(
          children: [
            SettingsTile(
              key: WidgetsScreen.howKey,
              title: l10n.widgetHowTitle,
              detail: l10n.widgetHowDetail,
              chevron: true,
              onTap: () => context.go(AppPaths.settingsWidgetsHow),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CaptionText(l10n.widgetsStaleNote),
      ],
    );
  }

  Widget _item(
    BuildContext context, {
    required HomeWidgetKind kind,
    required String title,
    required String detail,
    required bool canPin,
    required Widget child,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        CaptionText(detail),
      ],
    );
    final button = OutlinedButton(
      key: WidgetsScreen.pinKey(kind),
      onPressed: () => unawaited(_pin(kind)),
      child: Text(l10n.widgetCatalogAdd),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: 8),
        _headerRow(context, label, button, canPin: canPin),
        if (_requested == kind) ...[
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: CaptionText(l10n.widgetPinRequested),
          ),
        ],
        if (_failed == kind) ...[
          const SizedBox(height: 4),
          Semantics(liveRegion: true, child: CaptionText(l10n.widgetPinFailed)),
        ],
      ],
    );
  }

  Widget _headerRow(
    BuildContext context,
    Widget label,
    Widget button, {
    required bool canPin,
  }) {
    if (!canPin) return label;
    if (context.prefersSingleColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label, const SizedBox(height: 6), button],
      );
    }
    return Row(
      children: [
        Expanded(child: label),
        const SizedBox(width: 12),
        button,
      ],
    );
  }

  String _thisWeekDetail(
    AppLocalizations l10n, {
    required bool hasEffort,
    required bool hasGoals,
  }) {
    if (hasEffort && hasGoals) return l10n.widgetThisWeekCatalogBoth;
    if (hasEffort) return l10n.widgetThisWeekCatalogEffort;
    return l10n.widgetThisWeekCatalogGoals;
  }

  Future<void> _pin(HomeWidgetKind kind) async {
    bool ok;
    try {
      await ref.read(widgetGatewayProvider).pin(kind);
      ok = true;
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _requested = ok ? kind : null;
      _failed = ok ? null : kind;
    });
  }

  static Brightness _previewBrightness(
    BuildContext context,
    WidgetTheme theme,
  ) => switch (theme) {
    WidgetTheme.dark => Brightness.dark,
    WidgetTheme.light => Brightness.light,
    WidgetTheme.app => Theme.of(context).brightness,
  };
}
