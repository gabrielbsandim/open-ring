import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_preview.dart';
import 'package:open_ring/features/widgets/presentation/widget_previews.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class WidgetsScreen extends ConsumerWidget {
  const new({super.key});

  static const configureKey = Key('widgets_configure_today');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(widgetSnapshotProvider).value;
    final now = ref.watch(clockProvider)();
    final config = ref.watch(todayWidgetConfigProvider);
    final readiness = _Described(
      detail: l10n.widgetReadinessDetail,
      child: ReadinessWidgetPreview(snapshot: snapshot, now: now),
    );
    final ring = _Described(
      detail: l10n.widgetRingDetail,
      child: RingWidgetPreview(snapshot: snapshot, now: now),
    );
    return AppPage(
      title: l10n.widgetsTitle,
      children: [
        BodyText(l10n.widgetsIntro),
        SectionHeader(l10n.widgetsAndroid),
        if (context.prefersSingleColumn) ...[
          readiness,
          const SizedBox(height: 12),
          ring,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: readiness),
              const SizedBox(width: 12),
              Expanded(child: ring),
            ],
          ),
        const SizedBox(height: 12),
        _Described(
          detail: l10n.widgetTodayDetail,
          child: TodayWidgetPreview(
            config: config,
            snapshot: snapshot,
            brightness: _previewBrightness(context, config.theme),
            now: now,
          ),
        ),
        const SizedBox(height: 12),
        _Described(
          detail: l10n.widgetWorkoutDetail,
          child: WorkoutWidgetPreview(snapshot: snapshot, now: now),
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.widgetsStaleNote),
        const SizedBox(height: cardGap),
        TileGroup(
          children: [
            SettingsTile(
              key: configureKey,
              title: l10n.widgetConfigureToday,
              detail: l10n.widgetConfigureTodayDetail,
              chevron: true,
              onTap: () => context.go(AppPaths.settingsWidgetToday),
            ),
          ],
        ),
      ],
    );
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

class _Described extends StatelessWidget {
  const new({required this.detail, required this.child});

  final String detail;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [child, const SizedBox(height: 6), CaptionText(detail)],
  );
}
