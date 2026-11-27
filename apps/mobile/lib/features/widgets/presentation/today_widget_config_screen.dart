import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_preview.dart';
import 'package:open_ring/features/widgets/presentation/widget_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class TodayWidgetConfigScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const addKey = Key('today_widget_add');
  static const requestedKey = Key('today_widget_requested');
  static const pinFailedKey = Key('today_widget_pin_failed');

  static Key metricKey(WidgetMetric metric) =>
      Key('today_widget_metric_${metric.name}');

  static Key addMetricKey(WidgetMetric metric) =>
      Key('today_widget_add_${metric.name}');

  static Key moveUpKey(WidgetMetric metric) =>
      Key('today_widget_up_${metric.name}');

  static Key moveDownKey(WidgetMetric metric) =>
      Key('today_widget_down_${metric.name}');

  static Key removeMetricKey(WidgetMetric metric) =>
      Key('today_widget_remove_${metric.name}');

  static Key previewSizeKey(TodayPreviewSize size) =>
      Key('today_widget_size_${size.name}');

  static Key themeKey(WidgetTheme theme) =>
      Key('today_widget_theme_${theme.name}');

  @override
  ConsumerState<TodayWidgetConfigScreen> createState() => _ConfigState();
}

class _ConfigState extends ConsumerState<TodayWidgetConfigScreen> {
  TodayPreviewSize _previewSize = TodayPreviewSize.medium;
  bool _requested = false;
  bool _pinFailed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(todayWidgetConfigProvider);
    final modules = ref.watch(activeModulesProvider);
    final hideNumbers = ref.watch(profileWeightHiddenProvider);
    final units = ref.watch(currentUnitSystemProvider);
    final effective = TodayWidgetConfig(
      metrics: config.effectiveMetrics(
        enabled: modules,
        hideNumbers: hideNumbers,
      ),
      theme: config.theme,
    );
    final brightness = _previewBrightness(context, config.theme);
    return AppPage(
      title: l10n.widgetTodayTitle,
      subtitle: l10n.widgetsAndroid,
      children: [
        ChoiceRow<TodayPreviewSize>(
          values: TodayPreviewSize.values,
          selected: _previewSize,
          keyOf: TodayWidgetConfigScreen.previewSizeKey,
          label: (size) => switch (size) {
            TodayPreviewSize.small => l10n.widgetPreviewSizeSmall,
            TodayPreviewSize.medium => l10n.widgetPreviewSizeMedium,
            TodayPreviewSize.large => l10n.widgetPreviewSizeLarge,
          },
          onSelected: (size) => setState(() => _previewSize = size),
        ),
        const SizedBox(height: 12),
        TodayWidgetPreview(
          config: effective,
          snapshot: ref.watch(widgetSnapshotProvider).value,
          brightness: brightness,
          now: ref.watch(clockProvider)(),
          size: _previewSize,
          units: units,
        ),
        const SizedBox(height: 8),
        CaptionText(
          _themeNote(l10n, config.theme, brightness),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: cardGap),
        _ChosenFieldsCard(
          config: config,
          active: effective.metrics.toSet(),
          hideNumbers: hideNumbers,
        ),
        const SizedBox(height: cardGap),
        _AddFieldsCard(
          config: config,
          enabledModules: modules,
          hideNumbers: hideNumbers,
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(context, l10n.widgetTheme),
              const SizedBox(height: 10),
              ChoiceRow<WidgetTheme>(
                values: WidgetTheme.values,
                selected: config.theme,
                keyOf: TodayWidgetConfigScreen.themeKey,
                label: (theme) => theme.label(l10n),
                onSelected: (theme) => unawaited(
                  ref
                      .read(todayWidgetConfigProvider.notifier)
                      .selectTheme(theme),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        _addSection(context, l10n, disabled: effective.isEmpty),
      ],
    );
  }

  Brightness _previewBrightness(BuildContext context, WidgetTheme theme) =>
      switch (theme) {
        WidgetTheme.app => Theme.of(context).brightness,
        WidgetTheme.dark => Brightness.dark,
        WidgetTheme.light => Brightness.light,
      };

  String _themeNote(
    AppLocalizations l10n,
    WidgetTheme theme,
    Brightness brightness,
  ) => switch ((theme, brightness)) {
    (WidgetTheme.app, Brightness.dark) => l10n.widgetThemeNoteAppDark,
    (WidgetTheme.app, Brightness.light) => l10n.widgetThemeNoteAppLight,
    (WidgetTheme.dark, _) => l10n.widgetThemeNoteDark,
    (WidgetTheme.light, _) => l10n.widgetThemeNoteLight,
  };

  Widget _addSection(
    BuildContext context,
    AppLocalizations l10n, {
    required bool disabled,
  }) {
    final canPin = ref.watch(widgetPinSupportedProvider).value ?? false;
    if (!canPin) return CaptionText(l10n.widgetPinUnsupported);
    if (_requested) return const _RequestedCard();
    final button = FilledButton(
      key: TodayWidgetConfigScreen.addKey,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      onPressed: disabled ? null : _pin,
      child: Text(l10n.widgetAdd, textAlign: TextAlign.center),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pinFailed) ...[
          InfoNote(
            key: TodayWidgetConfigScreen.pinFailedKey,
            icon: Icons.error_outline_rounded,
            accent: AppColors.of(context).heart,
            text: l10n.widgetPinFailed,
            live: true,
          ),
          const SizedBox(height: cardGap),
        ],
        button,
        const SizedBox(height: 8),
        CaptionText(l10n.widgetPinNote),
      ],
    );
  }

  Future<void> _pin() async {
    final requested = await _requestPin();
    if (!mounted) return;
    setState(() {
      _requested = requested;
      _pinFailed = !requested;
    });
  }

  Future<bool> _requestPin() async {
    try {
      await ref.read(widgetGatewayProvider).pin(HomeWidgetKind.today);
      return true;
    } on Object {
      return false;
    }
  }
}

Widget _heading(BuildContext context, String text) => Semantics(
  header: true,
  child: Text(
    text,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w600),
  ),
);

class _ChosenFieldsCard extends ConsumerWidget {
  const new({
    required this.config,
    required this.active,
    required this.hideNumbers,
  });

  final TodayWidgetConfig config;
  final Set<WidgetMetric> active;
  final bool hideNumbers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(todayWidgetConfigProvider.notifier);
    var visibleIndex = 0;
    final rows = <Widget>[];
    for (var i = 0; i < config.metrics.length; i++) {
      final metric = config.metrics[i];
      final hidden = !active.contains(metric);
      final badge = _badgeLabel(
        l10n,
        hidden: hidden,
        visibleIndex: visibleIndex,
      );
      if (!hidden) visibleIndex++;
      rows.add(
        _row(
          context,
          notifier,
          index: i,
          metric: metric,
          badge: badge,
          hidden: hidden,
        ),
      );
    }
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              _heading(context, l10n.widgetMetrics),
              Semantics(
                liveRegion: true,
                child: CaptionText(
                  l10n.widgetMetricsCount(
                    active.length,
                    TodayWidgetConfig.maxMetrics,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CaptionText(l10n.widgetFieldsOrderNote),
          if (config.isEmpty) ...[
            const SizedBox(height: 10),
            BodyText(l10n.widgetNoMetrics),
          ],
          if (!config.isEmpty) ..._separated(context, rows),
        ],
      ),
    );
  }

  List<Widget> _separated(BuildContext context, List<Widget> rows) {
    final track = AppColors.of(context).track;
    return [
      for (final (idx, row) in rows.indexed) ...[
        if (idx > 0) Divider(height: 1, color: track),
        row,
      ],
    ];
  }

  String _badgeLabel(
    AppLocalizations l10n, {
    required bool hidden,
    required int visibleIndex,
  }) {
    if (hidden) return l10n.widgetBadgeHidden;
    if (visibleIndex == 0) return l10n.widgetBadgeSmallMediumLarge;
    if (visibleIndex < 3) return l10n.widgetBadgeMediumLarge;
    return l10n.widgetBadgeLarge;
  }

  Widget _row(
    BuildContext context,
    TodayWidgetConfigController notifier, {
    required int index,
    required WidgetMetric metric,
    required String badge,
    required bool hidden,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final name = metric.label(l10n);
    final lead = [
      SizedBox(
        width: 22,
        child: Text(
          '${index + 1}',
          style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
        ),
      ),
      AccentDot(color: metric.accent(colors)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
            if (hidden && hideNumbers && metric == WidgetMetric.energy)
              CaptionText(l10n.widgetEnergyHiddenNote),
          ],
        ),
      ),
    ];
    final controls = [
      DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceInner,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            badge,
            style: textTheme.labelSmall?.copyWith(
              color: hidden ? colors.textLabel : colors.textSecondary,
            ),
          ),
        ),
      ),
      _action(
        TodayWidgetConfigScreen.moveUpKey(metric),
        Icons.keyboard_arrow_up_rounded,
        l10n.widgetFieldMoveUp(name),
        index == 0 ? null : () => unawaited(notifier.moveUp(index)),
      ),
      _action(
        TodayWidgetConfigScreen.moveDownKey(metric),
        Icons.keyboard_arrow_down_rounded,
        l10n.widgetFieldMoveDown(name),
        index == config.metrics.length - 1
            ? null
            : () => unawaited(notifier.moveDown(index)),
      ),
      _action(
        TodayWidgetConfigScreen.removeMetricKey(metric),
        Icons.close_rounded,
        l10n.widgetFieldRemove(name),
        () => unawaited(notifier.remove(metric)),
      ),
    ];
    return Padding(
      key: TodayWidgetConfigScreen.metricKey(metric),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: context.prefersSingleColumn
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: lead),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: controls,
                ),
              ],
            )
          : Row(children: [...lead, const SizedBox(width: 6), ...controls]),
    );
  }

  Widget _action(
    Key key,
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
  ) => IconButton(
    key: key,
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon, size: 18),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
    visualDensity: VisualDensity.compact,
  );
}

class _AddFieldsCard extends ConsumerWidget {
  const new({
    required this.config,
    required this.enabledModules,
    required this.hideNumbers,
  });

  final TodayWidgetConfig config;
  final Set<ModuleId> enabledModules;
  final bool hideNumbers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ringOptions = [
      for (final m in WidgetMetric.values)
        if (m.module == null && !config.contains(m)) m,
    ];
    final moduleOptions = [
      for (final m in WidgetMetric.values)
        if (m.module != null &&
            enabledModules.contains(m.module) &&
            !config.contains(m))
          m,
    ];
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(context, l10n.widgetAddFieldHeading),
          if (config.isFull) ...[
            const SizedBox(height: 6),
            CaptionText(l10n.widgetFieldsLimitFull),
          ],
          const SizedBox(height: 10),
          CaptionText(l10n.widgetFromRing),
          if (ringOptions.isEmpty) ...[
            const SizedBox(height: 4),
            CaptionText(l10n.widgetAllRingAdded),
          ],
          for (final m in ringOptions) _row(context, ref, l10n, m),
          if (moduleOptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            CaptionText(l10n.widgetFromModules),
            for (final m in moduleOptions) _row(context, ref, l10n, m),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    WidgetMetric metric,
  ) {
    final colors = AppColors.of(context);
    final hiddenEnergy = metric == WidgetMetric.energy && hideNumbers;
    final enabled = !config.isFull && !hiddenEnergy;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SettingsTile(
        key: TodayWidgetConfigScreen.addMetricKey(metric),
        leading: AccentDot(color: metric.accent(colors)),
        title: metric.label(l10n),
        detail: _noteFor(l10n, metric),
        trailing: Icon(Icons.add_rounded, color: colors.textLabel, size: 20),
        onTap: enabled
            ? () => unawaited(
                ref.read(todayWidgetConfigProvider.notifier).add(metric),
              )
            : null,
      ),
    );
  }

  String? _noteFor(AppLocalizations l10n, WidgetMetric metric) =>
      switch (metric) {
        WidgetMetric.dayScore => l10n.widgetNoteDayScore,
        WidgetMetric.weight =>
          hideNumbers
              ? l10n.widgetNoteWeightHidden
              : l10n.widgetNoteWeightTrend,
        WidgetMetric.energy =>
          hideNumbers ? l10n.widgetNoteEnergyHidden : l10n.widgetNoteEnergy,
        WidgetMetric.effort => l10n.widgetNoteEffort,
        _ => null,
      };
}

class _RequestedCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      key: TodayWidgetConfigScreen.requestedKey,
      liveRegion: true,
      child: MetricCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline_rounded, color: colors.activity),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.widgetPinRequested,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.activity,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  BodyText(l10n.widgetPinNote),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
