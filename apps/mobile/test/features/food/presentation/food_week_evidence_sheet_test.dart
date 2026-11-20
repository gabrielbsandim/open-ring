import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/features/food/application/food_week.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/food_week_evidence_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const _monday = LocalDate(2026, 11, 9);

FoodWeekView _viewWith({
  required List<double> windows,
  required List<double> gaps,
  int? completeDays,
}) {
  final count = completeDays ?? windows.length;
  final days = [
    for (var i = 0; i < 7; i++)
      FoodWeekDayView(
        date: _monday.addDays(i),
        meals: const <Meal>[],
        complete: i < count,
        sleepOnset: null,
        windowMinutes: i < windows.length ? windows[i] : null,
        gapMinutes: i < gaps.length ? gaps[i] : null,
      ),
  ];
  final sortedW = [...windows]..sort();
  final sortedG = [...gaps]..sort();
  return FoodWeekView(
    monday: _monday,
    sunday: _monday.addDays(6),
    stats: FoodWeek(
      completeDays: count,
      records: count,
      windowMinutes: _median(sortedW),
      gapMinutes: _median(sortedG),
    ),
    plate: const PlateBuilding(completeDays: 0, mains: 0),
    softMode: false,
    days: days,
    completeWindows: sortedW,
    completeGaps: sortedG,
  );
}

double? _median(List<double> sorted) {
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

void main() {
  group('foodWeekEvidenceYours', () {
    testWidgets('formats single, odd, and even complete counts cleanly', (
      tester,
    ) async {
      await pumpScaled(
        tester,
        screenHost(const SizedBox()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
      );
      final format = MetricFormat.of(tester.element(find.byType(SizedBox)));

      expect(
        foodWeekEvidenceYours(format, [540], 540),
        format.l10n.foodSheetDaysYours(1, '9 h', '9 h'),
      );
      expect(
        foodWeekEvidenceYours(format, [60, 120, 210], 120),
        format.l10n.foodSheetDaysYours(3, '1 h, 2 h, 3 h 30 min', '2 h'),
      );
      expect(
        foodWeekEvidenceYours(format, [600, 660, 720, 780], 690),
        format.l10n.foodSheetDaysYours(
          4,
          '10 h, 11 h, 12 h, 13 h',
          '11 h 30 min',
        ),
      );
    });
  });

  group('FoodWeekEvidenceSheet and showFoodWeekEvidence', () {
    testWidgets('window sheet renders kind, title, median, range, 5 sections, '
        'and closes cleanly', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final view = _viewWith(
        windows: const [600, 660, 720, 780],
        gaps: const [120, 180],
      );

      late BuildContext hostContext;
      await pumpScaled(
        tester,
        screenHost(
          Builder(
            builder: (context) {
              hostContext = context;
              return ElevatedButton(
                onPressed: () => showFoodWeekEvidence(
                  context,
                  kind: FoodWeekEvidence.window,
                  view: view,
                ),
                child: const Text('open'),
              );
            },
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
      );

      final f = MetricFormat.of(hostContext);
      final range = l10n.metricTimeRange(
        f.monthDay(view.monday),
        f.monthDay(view.sunday),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsOneWidget);
      expect(find.byKey(FoodWeekEvidenceKeys.kind), findsOneWidget);
      expect(find.text(l10n.foodSheetKind), findsOneWidget);
      expect(find.text(l10n.foodWindowTitle), findsOneWidget);
      expect(find.text('11 h 30 min'), findsOneWidget);
      expect(find.text(l10n.foodSheetUnitMedian), findsOneWidget);
      expect(find.text(range), findsOneWidget);
      expect(find.byType(EnergyEvidenceSection), findsNWidgets(5));
      expect(find.text(l10n.foodSheetWindowWhat), findsOneWidget);
      expect(
        find.text(
          foodWeekEvidenceYours(
            f,
            view.completeWindows,
            view.stats.windowMinutes!,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text('${l10n.foodSheetWindowRule}\n\n${l10n.foodSheetMedianMath}'),
        findsOneWidget,
      );
      expect(find.text(l10n.foodSheetWindowOurs), findsOneWidget);
      expect(find.text(l10n.foodSheetWindowLimits), findsOneWidget);

      await tester.ensureVisible(find.byKey(FoodWeekEvidenceKeys.close));
      await tester.tap(find.byKey(FoodWeekEvidenceKeys.close));
      await tester.pumpAndSettle();

      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsNothing);
    });

    testWidgets('gap sheet renders odd sorted gaps and exact median', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final view = _viewWith(
        windows: const [660, 720, 750],
        gaps: const [90, 150, 210],
      );

      await pumpScaled(
        tester,
        screenHost(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFoodWeekEvidence(
                context,
                kind: FoodWeekEvidence.gap,
                view: view,
              ),
              child: const Text('open'),
            ),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsOneWidget);
      expect(find.text(l10n.foodWeekGapTitle), findsOneWidget);
      expect(find.text('2 h 30 min'), findsOneWidget);
      expect(find.text(l10n.foodSheetGapWhat), findsOneWidget);
      expect(
        find.text('${l10n.foodSheetGapRule}\n\n${l10n.foodSheetMedianMath}'),
        findsOneWidget,
      );
      expect(find.text(l10n.foodSheetGapOurs), findsOneWidget);
      expect(find.text(l10n.foodSheetGapLimits), findsOneWidget);
    });

    testWidgets('is a no-op when median is null or values list is empty', (
      tester,
    ) async {
      final emptyView = _viewWith(windows: const [], gaps: const []);

      await pumpScaled(
        tester,
        screenHost(
          Builder(
            builder: (context) => Row(
              children: [
                ElevatedButton(
                  onPressed: () => showFoodWeekEvidence(
                    context,
                    kind: FoodWeekEvidence.window,
                    view: emptyView,
                  ),
                  child: const Text('win'),
                ),
                ElevatedButton(
                  onPressed: () => showFoodWeekEvidence(
                    context,
                    kind: FoodWeekEvidence.gap,
                    view: emptyView,
                  ),
                  child: const Text('gap'),
                ),
              ],
            ),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
      );

      await tester.tap(find.text('win'));
      await tester.pumpAndSettle();
      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsNothing);

      await tester.tap(find.text('gap'));
      await tester.pumpAndSettle();
      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsNothing);
    });
  });
}
