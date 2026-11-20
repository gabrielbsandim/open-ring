import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/food_week.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/food_timing_chart.dart';
import 'package:open_ring/features/food/presentation/food_week_evidence_sheet.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';

enum FoodSection { day, week }

const _thumbRadius = BorderRadius.all(Radius.circular(6));

abstract final class FoodWeekKeys {
  static const tabs = Key('food_section_tabs');
  static const tabDay = Key('food_tab_day');
  static const tabWeek = Key('food_tab_week');
  static const contactSheet = Key('food_week_contact_sheet');
  static const empty = Key('food_week_empty');
  static const timingCard = Key('food_week_timing_card');
  static const timingChart = Key('food_week_timing_chart');
  static const windowRow = Key('food_week_window_row');
  static const gapRow = Key('food_week_gap_row');
  static const plateCard = Key('food_week_plate_card');
  static const softModeCard = Key('food_week_soft_mode_card');

  static Key dayColumn(LocalDate day) => Key('food_week_day_${day.iso}');
  static Key dayDot(LocalDate day) => Key('food_week_dot_${day.iso}');
  static Key emptyDay(LocalDate day) => Key('food_week_empty_${day.iso}');
  static Key thumb(int id) => Key('food_week_thumb_$id');
  static Key thumbPhoto(int id) => Key('food_week_thumb_photo_$id');
  static Key thumbNoPhoto(int id) => Key('food_week_thumb_no_photo_$id');
  static Key thumbMissingPhoto(int id) =>
      Key('food_week_thumb_missing_photo_$id');
}

class FoodSectionTabs extends StatelessWidget {
  const new({required this.current, super.key});

  final FoodSection current;

  @override
  Widget build(BuildContext context) {
    final l = MetricFormat.of(context).l10n;
    return SegmentedButton<FoodSection>(
      key: FoodWeekKeys.tabs,
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: FoodSection.day,
          label: Text(l.foodTabDay, key: FoodWeekKeys.tabDay),
        ),
        ButtonSegment(
          value: FoodSection.week,
          label: Text(l.foodTabWeek, key: FoodWeekKeys.tabWeek),
        ),
      ],
      selected: {current},
      onSelectionChanged: (picked) {
        final target = picked.first;
        if (target == current) return;
        final path = target == FoodSection.day
            ? AppPaths.food
            : AppPaths.foodWeek;
        GoRouter.maybeOf(context)?.go(path);
      },
    );
  }
}

class FoodWeekScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = MetricFormat.of(context).l10n.foodTitle;
    if (!ref.watch(foodEnabledProvider)) {
      return AppPage(title: title, children: const []);
    }
    return AppPage(title: title, children: const [_FoodWeekBody()]);
  }
}

class _FoodWeekBody extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_FoodWeekBody> createState() => _FoodWeekBodyState();
}

class _FoodWeekBodyState extends ConsumerState<_FoodWeekBody> {
  late final AppLifecycleListener _lifecycle;
  final Set<String> _broken = {};

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(currentFoodDayProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _markBroken(String name) {
    if (!mounted || !_broken.add(name)) return;
    setState(() {});
  }

  void _openMeal(int id) {
    final router = GoRouter.maybeOf(context);
    if (router != null) unawaited(router.push(AppPaths.foodMealOf(id)));
  }

  @override
  Widget build(BuildContext context) {
    final f = MetricFormat.of(context);
    final week = ref.watch(foodWeekProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FoodSectionTabs(current: FoodSection.week),
        const SizedBox(height: cardGap),
        ..._body(context, week, f),
      ],
    );
  }

  List<Widget> _body(
    BuildContext context,
    AsyncValue<FoodWeekView> week,
    MetricFormat f,
  ) {
    if (week.hasValue && !week.hasError) {
      final view = week.requireValue;
      final c = AppColors.of(context);
      final t = Theme.of(context).textTheme;
      return [
        _contactSheet(view, f, t, c),
        const SizedBox(height: cardGap),
        _timingCard(context, view, f, t, c),
        const SizedBox(height: cardGap),
        if (view.softMode)
          _card(FoodWeekKeys.softModeCard, [
            AccentTitle(title: f.l10n.foodWeekSoftTitle, accent: c.activity),
            const SizedBox(height: 8),
            BodyText(f.l10n.foodWeekSoftBody),
          ])
        else
          _plateCard(view.plate, f, t, c),
      ];
    }
    if (week.hasError) return [BodyText(f.l10n.metricLoadError)];
    return const [SizedBox(height: 96)];
  }

  Widget _contactSheet(
    FoodWeekView view,
    MetricFormat f,
    TextTheme t,
    AppColors c,
  ) {
    final l = f.l10n;
    final range = l.metricTimeRange(
      f.monthDay(view.monday),
      f.monthDay(view.sunday),
    );
    return _card(FoodWeekKeys.contactSheet, [
      _header(
        Text(range, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        l.foodWeekLast,
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < view.days.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _dayCol(view.days[i], f, t, c)),
          ],
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _legend(l.foodWeekCompleteLegend, true, c),
          _legend(l.foodWeekIncompleteLegend, false, c),
        ],
      ),
      const SizedBox(height: 8),
      if (view.stats.records == 0)
        Text(
          l.foodWeekEmpty,
          key: FoodWeekKeys.empty,
          style: t.bodyMedium?.copyWith(color: c.textSecondary),
        )
      else
        CaptionText(
          l.foodWeekSummary(view.stats.completeDays, view.stats.records),
        ),
    ]);
  }

  Widget _dayCol(
    FoodWeekDayView day,
    MetricFormat f,
    TextTheme t,
    AppColors c,
  ) {
    return Column(
      key: FoodWeekKeys.dayColumn(day.date),
      children: [
        _fit(CaptionText(f.weekday(day.date), textAlign: TextAlign.center)),
        _fit(
          Text(
            '${day.date.day}',
            style: numberStyle(t.bodySmall, color: c.textSecondary),
          ),
        ),
        const SizedBox(height: 4),
        _dot(day.complete, c, key: FoodWeekKeys.dayDot(day.date)),
        const SizedBox(height: 6),
        ..._daySlots(day, f, c),
      ],
    );
  }

  List<Widget> _daySlots(FoodWeekDayView day, MetricFormat f, AppColors c) {
    if (day.meals.isEmpty) {
      return [
        AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(
            key: FoodWeekKeys.emptyDay(day.date),
            painter: _DashedBoxPainter(color: c.surfaceBorder),
          ),
        ),
      ];
    }
    final dayText = f.date(day.date);
    return [
      for (var i = 0; i < day.meals.length; i++) ...[
        if (i > 0) const SizedBox(height: 4),
        _thumb(day.meals[i], dayText, f, c),
      ],
    ];
  }

  Widget _thumb(Meal m, String dayText, MetricFormat f, AppColors c) {
    final l = f.l10n;
    final label = l.foodWeekThumbLabel(
      dayText,
      mealSlotLabel(l, m),
      f.clock(m.entry.at, Duration.zero),
    );
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: c.surfaceInner,
        clipBehavior: Clip.antiAlias,
        borderRadius: _thumbRadius,
        child: InkWell(
          key: FoodWeekKeys.thumb(m.id),
          onTap: () => _openMeal(m.id),
          child: AspectRatio(
            aspectRatio: 1,
            child: ExcludeSemantics(child: _thumbBody(m, c)),
          ),
        ),
      ),
    );
  }

  Widget _thumbBody(Meal m, AppColors c) {
    final name = m.photo;
    if (name == null) {
      return _glyph(
        Icons.restaurant_outlined,
        FoodWeekKeys.thumbNoPhoto(m.id),
        c,
      );
    }
    final photo = _broken.contains(name)
        ? null
        : ref.watch(mealPhotoProvider(name));
    if (photo != null && photo.isLoading && !photo.hasValue) {
      return const SizedBox.expand();
    }
    final bytes = photo != null && photo.hasValue ? photo.requireValue : null;
    if (bytes == null) {
      return _glyph(
        Icons.broken_image_outlined,
        FoodWeekKeys.thumbMissingPhoto(m.id),
        c,
      );
    }
    return Image(
      key: FoodWeekKeys.thumbPhoto(m.id),
      image: ResizeImage(MemoryImage(bytes), width: 96),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _markBroken(name));
        return const SizedBox.shrink();
      },
    );
  }
}

Widget _glyph(IconData d, Key k, AppColors c) =>
    Icon(d, key: k, size: 16, color: c.textLabel);

Widget _fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, child: child);

Widget _card(Key key, List<Widget> children) => MetricCard(
  key: key,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  ),
);

Widget _header(Widget leading, String tag) => Wrap(
  alignment: WrapAlignment.spaceBetween,
  crossAxisAlignment: WrapCrossAlignment.center,
  spacing: 8,
  runSpacing: 4,
  children: [leading, CaptionText(tag)],
);

Widget _dot(bool complete, AppColors c, {Key? key}) => SizedBox(
  key: key,
  width: 6,
  height: 6,
  child: DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: complete ? c.activity : null,
      border: complete ? null : Border.all(color: c.textLabel, width: 1.2),
    ),
  ),
);

Widget _legend(String label, bool complete, AppColors c) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    _dot(complete, c),
    const SizedBox(width: 5),
    Flexible(child: CaptionText(label)),
  ],
);

Widget _timingCard(
  BuildContext context,
  FoodWeekView view,
  MetricFormat f,
  TextTheme t,
  AppColors c,
) {
  final l = f.l10n;
  return _card(FoodWeekKeys.timingCard, [
    _header(
      AccentTitle(title: l.foodTimingTitle, accent: c.activity),
      l.foodTimingCompleteDays(view.stats.completeDays),
    ),
    const SizedBox(height: 12),
    FoodTimingChart(
      key: FoodWeekKeys.timingChart,
      days: view.days,
      completeDays: view.stats.completeDays,
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        _timingLegend(12, 6, 3, c.activity, l.foodTimingLegendWindow),
        _timingLegend(3, 12, 2, c.sleep, l.foodTimingLegendSleep),
      ],
    ),
    const SizedBox(height: 12),
    _timingRow(context, FoodWeekEvidence.window, view),
    _timingRow(context, FoodWeekEvidence.gap, view),
  ]);
}

Widget _timingLegend(double w, double h, double r, Color color, String label) =>
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.all(Radius.circular(r)),
          ),
          child: SizedBox(width: w, height: h),
        ),
        const SizedBox(width: 6),
        Flexible(child: CaptionText(label)),
      ],
    );

Widget _timingRow(
  BuildContext context,
  FoodWeekEvidence kind,
  FoodWeekView view,
) {
  final f = MetricFormat.of(context);
  final l = f.l10n;
  final c = AppColors.of(context);
  final t = Theme.of(context).textTheme;
  final win = kind == FoodWeekEvidence.window;
  final m = win ? view.stats.windowMinutes : view.stats.gapMinutes;
  final value = m == null
      ? l.metricNoReading
      : f.duration(Duration(minutes: m.round()));
  final onTap = m == null
      ? null
      : () => unawaited(showFoodWeekEvidence(context, kind: kind, view: view));
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Divider(height: 1, color: c.surfaceBorder),
      InkWell(
        key: win ? FoodWeekKeys.windowRow : FoodWeekKeys.gapRow,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            win ? l.foodWindowTitle : l.foodWeekGapTitle,
                            style: t.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            value,
                            style: numberStyle(
                              t.bodyMedium,
                              color: onTap == null
                                  ? c.textLabel
                                  : c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      CaptionText(win ? l.foodWeekWindowSub : l.foodWeekGapSub),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: c.textLabel,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _plateCard(PlateResult plate, MetricFormat f, TextTheme t, AppColors c) {
  final l = f.l10n;
  final rows = switch (plate) {
    final PlatePattern p => [
      Text(
        l.foodPlateSummary(
          f.decimal(p.score, digits: 1),
          p.mains,
          p.completeDays,
        ),
        style: numberStyle(t.titleMedium),
      ),
      const SizedBox(height: 6),
      BodyText(
        l.foodPlateCounts(
          p.protein,
          p.veg,
          p.processed,
          p.sugaryDays,
          l.foodPlateDrinks(f.points(p.drinks)),
        ),
      ),
    ],
    final PlateBuilding b => [
      BodyText(
        l.foodPlateBuilding(
          plateMinCompleteDays,
          plateMinMains,
          b.completeDays,
          b.mains,
        ),
      ),
    ],
  };
  return _card(FoodWeekKeys.plateCard, [
    _header(
      AccentTitle(title: l.foodPlateTitle, accent: c.activity),
      l.foodPlateTag,
    ),
    const SizedBox(height: 10),
    ...rows,
    const SizedBox(height: 8),
    CaptionText(l.foodPlateNote),
  ]);
}

class _DashedBoxPainter extends CustomPainter {
  const new({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6.0) {
        canvas.drawPath(
          metric.extractPath(d, (d + 3.0).clamp(0.0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) => old.color != color;
}
