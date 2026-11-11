import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
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

  static Key themeKey(WidgetTheme theme) =>
      Key('today_widget_theme_${theme.name}');

  @override
  ConsumerState<TodayWidgetConfigScreen> createState() => _ConfigState();
}

class _ConfigState extends ConsumerState<TodayWidgetConfigScreen> {
  bool _requested = false;
  bool _pinFailed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(todayWidgetConfigProvider);
    final brightness = _previewBrightness(context, config.theme);
    return AppPage(
      title: l10n.widgetTodayTitle,
      subtitle: l10n.widgetTodaySize,
      children: [
        TodayWidgetPreview(
          config: config,
          snapshot: ref.watch(widgetSnapshotProvider).value,
          brightness: brightness,
          now: ref.watch(clockProvider)(),
        ),
        const SizedBox(height: 8),
        CaptionText(
          _themeNote(l10n, config.theme, brightness),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: cardGap),
        _MetricsCard(config: config),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Heading(l10n.widgetTheme),
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
        _addSection(context, l10n, config),
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
    AppLocalizations l10n,
    TodayWidgetConfig config,
  ) {
    final canPin = ref.watch(widgetPinSupportedProvider).value ?? false;
    if (!canPin) return CaptionText(l10n.widgetPinUnsupported);
    if (_requested) return const _RequestedCard();
    final button = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: FilledButton(
        key: TodayWidgetConfigScreen.addKey,
        onPressed: config.isEmpty ? null : _pin,
        child: Text(l10n.widgetAdd, textAlign: TextAlign.center),
      ),
    );
    if (!_pinFailed) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoNote(
          key: TodayWidgetConfigScreen.pinFailedKey,
          icon: Icons.error_outline_rounded,
          accent: AppColors.of(context).heart,
          text: l10n.widgetPinFailed,
          live: true,
        ),
        const SizedBox(height: cardGap),
        button,
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

class _Heading extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _MetricsCard extends ConsumerWidget {
  const new({required this.config});

  final TodayWidgetConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final toggles = [
      for (final metric in WidgetMetric.values)
        _MetricToggle(
          metric: metric,
          selected: config.contains(metric),
          enabled: config.canPick(metric),
          onTap: () => unawaited(
            ref.read(todayWidgetConfigProvider.notifier).toggle(metric),
          ),
        ),
    ];
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              _Heading(l10n.widgetMetrics),
              Semantics(
                liveRegion: true,
                child: CaptionText(
                  l10n.widgetMetricsCount(
                    config.metrics.length,
                    TodayWidgetConfig.maxMetrics,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _grid(context, toggles),
          const SizedBox(height: 12),
          CaptionText(_limitNote(l10n)),
        ],
      ),
    );
  }

  String _limitNote(AppLocalizations l10n) {
    if (config.isFull) return l10n.widgetLimitFull;
    if (config.isEmpty) return l10n.widgetLimitEmpty;
    return l10n.widgetLimitSome(config.remaining);
  }

  Widget _grid(BuildContext context, List<Widget> toggles) {
    if (context.prefersSingleColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, toggle) in toggles.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            toggle,
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < toggles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: toggles[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < toggles.length
                      ? toggles[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricToggle extends StatelessWidget {
  const new({
    required this.metric,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final WidgetMetric metric;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final foreground = enabled ? colors.textPrimary : colors.textLabel;
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        child: Material(
          key: TodayWidgetConfigScreen.metricKey(metric),
          color: selected ? colors.surfaceInner : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? colors.textPrimary : colors.strongBorder,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: foreground,
                    ),
                    const SizedBox(width: 8),
                    AccentDot(color: metric.accent(colors)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        metric.label(AppLocalizations.of(context)),
                        style: textTheme.bodyMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
