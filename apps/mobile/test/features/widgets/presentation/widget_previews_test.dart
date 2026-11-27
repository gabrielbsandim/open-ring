import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/widgets/presentation/this_week_widget_preview.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_preview.dart';
import 'package:open_ring/features/widgets/presentation/widget_labels.dart';
import 'package:open_ring/features/widgets/presentation/widget_previews.dart';
import 'package:open_ring/l10n/generated/app_localizations_en.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/settings_fakes.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  const today = LocalDate(2026, 12, 10);
  final now = DateTime(2026, 12, 10, 19, 30);
  final syncedAt = DateTime(2026, 12, 10, 19, 23);
  final format = MetricFormat(AppLocalizationsEn(), 'en');

  WidgetSnapshot v2Snapshot({
    SyncFreshness freshness = SyncFreshness.fresh,
    int? batteryPercent = 82,
    bool? batteryCharging,
    bool hideNumbers = false,
    WidgetDayScore? dayScore,
    WidgetWeight? weight = const WidgetWeight(
      direction: WidgetWeightDirection.falling,
      trendKilograms: 77.6,
    ),
    WidgetEnergy? energy = const WidgetEnergy(lowKcal: 1900, highKcal: 2600),
    WidgetEffort? effort = const WidgetEffort(
      points: 140,
      targetPoints: 150,
      strengthDays: 1,
      strengthTarget: 2,
    ),
    WidgetGoals? goals,
    Set<ModuleId> enabledModules = const {
      ModuleId.openScore,
      ModuleId.body,
      ModuleId.energy,
      ModuleId.effort,
      ModuleId.goals,
    },
  }) => WidgetSnapshot(
    date: today,
    freshness: freshness,
    syncedAt: freshness == SyncFreshness.neverSynced ? null : syncedAt,
    stepGoal: 10000,
    readiness: 72,
    restingHeartRate: 55,
    hrv: 48,
    sleepMinutes: 432,
    sleepScore: 78,
    steps: 8640,
    heartRateMean: 68,
    spo2: 96,
    stress: 31,
    batteryPercent: batteryPercent,
    batteryCharging: batteryCharging,
    hideNumbers: hideNumbers,
    dayScore:
        dayScore ??
        WidgetDayScore(
          kind: WidgetDayScoreKind.full,
          score: 81,
          band: DayScoreBand.good,
          coverage: 100,
          pillarPoints: const [23.4, 32.96, 14, 6, 5],
          asOf: now,
        ),
    weight: weight,
    energy: energy,
    effort: effort,
    enabledModules: enabledModules,
    goals:
        goals ??
        const WidgetGoals(
          state: WidgetGoalsState.running,
          monday: LocalDate(2026, 12, 7),
          sunday: LocalDate(2026, 12, 13),
          weekNumber: 4,
          blockWeeks: 12,
          levers: [
            WidgetGoalLever(
              kind: LeverKind.strengthDays,
              target: 2,
              achieved: 1,
              goal: 2,
              days: [
                LeverDayMark.met,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
                LeverDayMark.ahead,
              ],
            ),
            WidgetGoalLever(
              kind: LeverKind.steps,
              target: 10000,
              achieved: 2,
              goal: 5,
            ),
          ],
        ),
  );

  Future<void> pumpPreview(
    WidgetTester tester,
    Widget child, {
    LayoutCase? layout,
  }) => pumpScaled(
    tester,
    screenHost(Scaffold(body: SingleChildScrollView(child: child))),
    textScaler: layout?.textScaler ?? TextScaler.noScaling,
    brightness: layout?.brightness ?? Brightness.dark,
    locale: layout?.locale ?? const Locale('en'),
    overrides: settingsOverrides(),
  );

  group('widget_labels v2', () {
    test('describes dayScore, weight, energy, effort and unpaired mask', () {
      final snap = v2Snapshot();
      expect(
        WidgetMetric.dayScore.describe(format, snap, now: now).value,
        '81',
      );
      expect(WidgetMetric.weight.describe(format, snap).value, '77.6 kg');
      expect(
        WidgetMetric.weight
            .describe(
              format,
              v2Snapshot(hideNumbers: true),
              units: UnitSystem.imperial,
            )
            .value,
        'Going down',
      );
      expect(
        WidgetMetric.energy.describe(format, snap).value,
        '1,900 to 2,600',
      );
      expect(WidgetMetric.effort.describe(format, snap).value, '140');
      expect(
        WidgetMetric.effort.describe(format, snap).progress,
        closeTo(140 / 150, 0.001),
      );

      final unpaired = v2Snapshot(freshness: SyncFreshness.unpaired);
      expect(WidgetMetric.steps.describe(format, unpaired).value, '--');
      expect(WidgetMetric.weight.describe(format, unpaired).value, '77.6 kg');
      expect(WidgetMetric.energy.describe(format, unpaired).value, '--');
    });

    test('describeDayScore and ringPreviewStatus cover v2 states', () {
      expect(
        describeDayScore(
          format,
          v2Snapshot(
            dayScore: const WidgetDayScore(
              kind: WidgetDayScoreKind.firstDays,
              coverage: 45,
            ),
          ),
          now,
          stale: false,
        ).messageTitle,
        'Your first score is on its way',
      );
      expect(
        describeDayScore(
          format,
          v2Snapshot(
            dayScore: const WidgetDayScore(
              kind: WidgetDayScoreKind.noScore,
              coverage: 20,
              gap: DayScoreGap.coverage,
            ),
          ),
          now,
          stale: false,
        ).messageDetail,
        'Needs 60 points today.',
      );
      expect(
        ringPreviewStatus(
          format,
          v2Snapshot(batteryPercent: 63, batteryCharging: true),
          now,
        ).text,
        contains('charging'),
      );
      expect(
        ringPreviewStatus(format, v2Snapshot(batteryPercent: 20), now).text,
        contains('low battery'),
      );
    });
  });

  group('RingWidgetPreview and ReadinessWidgetPreview', () {
    testWidgets('Ring preview renders charging, low <= 20%, and stale states', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        RingWidgetPreview(
          snapshot: v2Snapshot(batteryPercent: 63, batteryCharging: true),
          now: now,
        ),
      );
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.textContaining('charging'), findsOneWidget);

      await pumpPreview(
        tester,
        RingWidgetPreview(snapshot: v2Snapshot(batteryPercent: 20), now: now),
      );
      expect(find.textContaining('low battery'), findsOneWidget);

      await pumpPreview(
        tester,
        RingWidgetPreview(
          snapshot: v2Snapshot(freshness: SyncFreshness.stale),
          now: now,
        ),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('Readiness unpaired preview renders empty message', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        ReadinessWidgetPreview(snapshot: null, now: now),
      );
      expect(find.text('Pair a ring to fill this widget.'), findsOneWidget);
      expect(find.text('No ring paired'), findsOneWidget);
    });
  });

  group('TodayWidgetPreview S/M/L and v2 states', () {
    final fullConfig = TodayWidgetConfig(
      metrics: const [
        WidgetMetric.dayScore,
        WidgetMetric.steps,
        WidgetMetric.sleep,
        WidgetMetric.effort,
        WidgetMetric.energy,
        WidgetMetric.weight,
      ],
    );

    testWidgets('Small shows 1st metric, Medium 3, Large all 6', (
      tester,
    ) async {
      final snap = v2Snapshot();
      await pumpPreview(
        tester,
        TodayWidgetPreview(
          config: fullConfig,
          snapshot: snap,
          brightness: Brightness.dark,
          now: now,
          size: TodayPreviewSize.small,
        ),
      );
      expect(find.text('81'), findsOneWidget);
      expect(find.text('77.6 kg'), findsNothing);

      await pumpPreview(
        tester,
        TodayWidgetPreview(
          config: fullConfig,
          snapshot: snap,
          brightness: Brightness.dark,
          now: now,
        ),
      );
      expect(find.text('81'), findsOneWidget);
      expect(find.text('8,640'), findsOneWidget);
      expect(find.text('140'), findsNothing);

      await pumpPreview(
        tester,
        TodayWidgetPreview(
          config: fullConfig,
          snapshot: snap,
          brightness: Brightness.dark,
          now: now,
          size: TodayPreviewSize.large,
        ),
      );
      expect(find.text('81'), findsOneWidget);
      expect(find.text('140'), findsOneWidget);
      expect(find.text('1,900 to 2,600'), findsOneWidget);
      expect(find.text('77.6 kg'), findsOneWidget);
    });

    testWidgets('Weight shows direction only when hideNumbers is true', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        TodayWidgetPreview(
          config: TodayWidgetConfig(metrics: const [WidgetMetric.weight]),
          snapshot: v2Snapshot(hideNumbers: true),
          brightness: Brightness.light,
          now: now,
          size: TodayPreviewSize.small,
          units: UnitSystem.imperial,
        ),
      );
      expect(find.text('Going down'), findsOneWidget);
      expect(find.textContaining('lb'), findsNothing);
    });

    testWidgets('Unpaired mixed keeps Weight and masks ring metrics', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        TodayWidgetPreview(
          config: TodayWidgetConfig(
            metrics: const [WidgetMetric.steps, WidgetMetric.weight],
          ),
          snapshot: v2Snapshot(freshness: SyncFreshness.unpaired),
          brightness: Brightness.dark,
          now: now,
        ),
      );
      expect(find.text('77.6 kg'), findsOneWidget);
      expect(find.text('--'), findsOneWidget);
      expect(find.text('No ring paired'), findsOneWidget);
    });

    testWidgets(
      'Day Score covers partial, firstDays, noScore, afterMidnight, stale',
      (tester) async {
        Future<void> pumpDayScore(
          WidgetDayScore ds, {
          SyncFreshness freshness = SyncFreshness.fresh,
        }) => pumpPreview(
          tester,
          TodayWidgetPreview(
            config: TodayWidgetConfig(metrics: const [WidgetMetric.dayScore]),
            snapshot: v2Snapshot(freshness: freshness, dayScore: ds),
            brightness: Brightness.dark,
            now: now,
            size: TodayPreviewSize.small,
          ),
        );

        await pumpDayScore(
          const WidgetDayScore(
            kind: WidgetDayScoreKind.partial,
            score: 83,
            band: DayScoreBand.good,
            coverage: 75,
          ),
        );
        expect(find.textContaining('75 of 100'), findsOneWidget);

        await pumpDayScore(
          const WidgetDayScore(
            kind: WidgetDayScoreKind.firstDays,
            coverage: 45,
          ),
        );
        expect(find.text('Your first score is on its way'), findsOneWidget);

        await pumpDayScore(
          const WidgetDayScore(
            kind: WidgetDayScoreKind.noScore,
            coverage: 20,
            gap: DayScoreGap.night,
          ),
        );
        expect(find.text('No score today'), findsOneWidget);

        await pumpDayScore(
          const WidgetDayScore(
            kind: WidgetDayScoreKind.afterMidnight,
            score: 83,
            band: DayScoreBand.good,
            coverage: 100,
          ),
        );
        expect(find.textContaining('yesterday, final'), findsOneWidget);

        await pumpDayScore(
          WidgetDayScore(
            kind: WidgetDayScoreKind.full,
            score: 76,
            band: DayScoreBand.good,
            coverage: 100,
            asOf: DateTime(2026, 12, 10, 14, 5),
          ),
          freshness: SyncFreshness.stale,
        );
        expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
      },
    );

    for (final layout in layoutMatrix()) {
      testWidgets('Large preview with all 6 fields lays out at $layout', (
        tester,
      ) async {
        await pumpPreview(
          tester,
          TodayWidgetPreview(
            config: fullConfig,
            snapshot: v2Snapshot(),
            brightness: layout.brightness,
            now: now,
            size: TodayPreviewSize.large,
          ),
          layout: layout,
        );
        expect(find.byKey(TodayWidgetPreview.previewKey), findsOneWidget);
      });
    }
  });

  group('ThisWeekWidgetPreview', () {
    testWidgets(
      'renders running, review, paused, hold, recovery, unpaired, and modules-off',
      (tester) async {
        await pumpPreview(
          tester,
          ThisWeekWidgetPreview(
            snapshot: v2Snapshot(),
            now: now,
            size: ThisWeekPreviewSize.large,
          ),
        );
        expect(find.text('140'), findsOneWidget);
        expect(find.text('of 150 · strength 1 of 2'), findsOneWidget);
        expect(find.text('week 4 of 12'), findsOneWidget);

        await pumpPreview(
          tester,
          ThisWeekWidgetPreview(
            snapshot: v2Snapshot(
              goals: const WidgetGoals(
                state: WidgetGoalsState.review,
                monday: LocalDate(2026, 12, 7),
                sunday: LocalDate(2026, 12, 13),
              ),
            ),
            now: now,
          ),
        );
        expect(find.text('The review of the week is ready'), findsOneWidget);

        for (final (state, expectedText) in [
          (WidgetGoalsState.paused, 'The plan stopped asking for changes'),
          (WidgetGoalsState.hold, 'The weight plan holds'),
          (WidgetGoalsState.recovery, 'This week the plan asks nothing'),
        ]) {
          await pumpPreview(
            tester,
            ThisWeekWidgetPreview(
              snapshot: v2Snapshot(
                effort: null,
                enabledModules: const {ModuleId.goals},
                goals: WidgetGoals(
                  state: state,
                  monday: const LocalDate(2026, 12, 7),
                  sunday: const LocalDate(2026, 12, 13),
                ),
              ),
              now: now,
              size: ThisWeekPreviewSize.small,
            ),
          );
          expect(find.textContaining(expectedText), findsOneWidget);
        }

        await pumpPreview(
          tester,
          ThisWeekWidgetPreview(
            snapshot: v2Snapshot(freshness: SyncFreshness.unpaired),
            now: now,
          ),
        );
        expect(find.text('No ring paired'), findsOneWidget);

        await pumpPreview(
          tester,
          ThisWeekWidgetPreview(
            snapshot: WidgetSnapshot(
              date: today,
              freshness: SyncFreshness.fresh,
              syncedAt: syncedAt,
              stepGoal: 10000,
            ),
            now: now,
          ),
        );
        expect(
          find.text('Effort and Goals are off. Tap to open Modules.'),
          findsOneWidget,
        );
      },
    );

    for (final layout in layoutMatrix()) {
      for (final previewSize in [
        ThisWeekPreviewSize.medium,
        ThisWeekPreviewSize.large,
      ]) {
        testWidgets(
          'ThisWeek ${previewSize.name} preview lays out at $layout',
          (tester) async {
            await pumpPreview(
              tester,
              ThisWeekWidgetPreview(
                snapshot: v2Snapshot(),
                now: now,
                size: previewSize,
              ),
              layout: layout,
            );
            expect(
              find.byKey(ThisWeekWidgetPreview.previewKey),
              findsOneWidget,
            );
          },
        );
      }
    }
  });
}
