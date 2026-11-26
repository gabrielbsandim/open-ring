import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_config_screen.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_preview.dart';
import 'package:open_ring/features/widgets/presentation/widget_previews.dart';
import 'package:open_ring/features/widgets/presentation/widgets_screen.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/settings_fakes.dart';
import '../../../helpers/widget_fakes.dart';

List<Override> widgetOverrides({
  MetricsScenario? scenario,
  FakeWidgetGateway? gateway,
  TodayWidgetConfig? config,
}) => [
  ...metricsOverrides(scenario ?? fullDataScenario),
  widgetGatewayProvider.overrideWithValue(gateway ?? FakeWidgetGateway()),
  todayWidgetConfigStoreProvider.overrideWithValue(
    InMemoryTodayWidgetConfigStore(config),
  ),
];

Future<void> pumpConfig(
  WidgetTester tester, {
  MetricsScenario? scenario,
  FakeWidgetGateway? gateway,
  TodayWidgetConfig? config,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(const TodayWidgetConfigScreen()),
  textScaler: TextScaler.noScaling,
  brightness: brightness,
  locale: const Locale('en'),
  size: const Size(360, 1600),
  overrides: widgetOverrides(
    scenario: scenario,
    gateway: gateway,
    config: config,
  ),
);

Future<void> pumpWidgets(WidgetTester tester, MetricsScenario scenario) =>
    pumpScaled(
      tester,
      screenHost(const WidgetsScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      size: const Size(360, 1600),
      overrides: widgetOverrides(scenario: scenario),
    );

String labelOf(WidgetTester tester, Key key) =>
    tester.getSemantics(find.byKey(key)).label;

WidgetSnapshot snapshotOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(WidgetsScreen)))
        .read(widgetSnapshotProvider)
        .value!;

String previewLabel(WidgetTester tester) =>
    tester.getSemantics(find.byKey(TodayWidgetPreview.previewKey)).label;

void main() {
  final layouts = <String, (Widget, List<Override> Function())>{
    'Widgets': (const WidgetsScreen(), widgetOverrides),
    'Widgets without a ring': (
      const WidgetsScreen(),
      () => widgetOverrides(scenario: noDataScenario),
    ),
    'Widgets paired with no data': (
      const WidgetsScreen(),
      () => widgetOverrides(
        scenario: MetricsScenario(nights: 0, activityDays: 0, ring: freshRing),
      ),
    ),
    'Widgets while stale': (
      const WidgetsScreen(),
      () => widgetOverrides(scenario: offlineScenario),
    ),
    'Today widget config': (const TodayWidgetConfigScreen(), widgetOverrides),
    'Today widget config with no metric': (
      const TodayWidgetConfigScreen(),
      () => widgetOverrides(config: TodayWidgetConfig(metrics: const [])),
    ),
    'Today widget config while stale': (
      const TodayWidgetConfigScreen(),
      () => widgetOverrides(scenario: offlineScenario),
    ),
    'Today widget config without a ring': (
      const TodayWidgetConfigScreen(),
      () => widgetOverrides(
        scenario: noDataScenario,
        gateway: FakeWidgetGateway(pinSupported: false),
      ),
    ),
  };

  for (final MapEntry(key: name, value: (screen, overrides))
      in layouts.entries) {
    for (final layout in layoutMatrix()) {
      testWidgets('$name lays out at $layout', (tester) async {
        await pumpScaled(
          tester,
          screenHost(screen),
          textScaler: layout.textScaler,
          brightness: layout.brightness,
          locale: layout.locale,
          overrides: overrides(),
        );
        await scrollThrough(tester);
      });
    }
  }

  group('Widgets previews', () {
    testWidgets('full data shows the user numbers from the snapshot', (
      tester,
    ) async {
      await pumpWidgets(tester, fullDataScenario);
      final snapshot = snapshotOf(tester);

      expect(snapshot.readiness, isNotNull);
      expect(
        labelOf(tester, ReadinessWidgetPreview.previewKey),
        contains('Readiness: ${snapshot.readiness}'),
      );
      expect(
        labelOf(tester, ReadinessWidgetPreview.previewKey),
        contains('Resting HR ${snapshot.restingHeartRate}'),
      );
      expect(find.byKey(TodayWidgetPreview.previewKey), findsOneWidget);
    });

    testWidgets('without a ring every preview is empty and says so', (
      tester,
    ) async {
      await pumpWidgets(tester, noDataScenario);

      for (final key in [
        ReadinessWidgetPreview.previewKey,
        RingWidgetPreview.previewKey,
      ]) {
        expect(labelOf(tester, key), isNot(matches(RegExp(r'\d'))));
      }
      expect(
        find.descendant(
          of: find.byKey(ReadinessWidgetPreview.previewKey),
          matching: find.text('Pair a ring to fill this widget.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ReadinessWidgetPreview.previewKey),
          matching: find.byType(LinearProgressIndicator),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(RingWidgetPreview.previewKey),
          matching: find.byType(LinearProgressIndicator),
        ),
        findsNothing,
      );
    });

    testWidgets('a paired ring with no score says it is not scored yet', (
      tester,
    ) async {
      await pumpWidgets(
        tester,
        MetricsScenario(nights: 0, activityDays: 0, ring: freshRing),
      );

      expect(find.text('Not scored yet'), findsOneWidget);
      expect(
        labelOf(tester, ReadinessWidgetPreview.previewKey),
        contains('Readiness: --'),
      );
    });

    testWidgets('the verdict band is never shown', (tester) async {
      await pumpWidgets(tester, fullDataScenario);

      for (final word in ['Good', 'Fair', 'Poor', 'Excellent', 'Boa']) {
        expect(find.text(word), findsNothing);
      }
    });

    const today = LocalDate(2026, 11, 10);
    final now = DateTime(2026, 11, 10, 9);

    Future<void> pumpWorkout(WidgetTester tester, WorkoutEntry? last) =>
        pumpScaled(
          tester,
          screenHost(
            Scaffold(
              body: WorkoutWidgetPreview(
                snapshot: WidgetSnapshot(
                  date: today,
                  freshness: SyncFreshness.fresh,
                  stepGoal: 8000,
                  syncedAt: now,
                  lastWorkout: last,
                ),
                now: now,
              ),
            ),
          ),
          textScaler: TextScaler.noScaling,
          brightness: Brightness.dark,
          locale: const Locale('en'),
          overrides: settingsOverrides(),
        );

    testWidgets('the workout preview shows the last real workout', (
      tester,
    ) async {
      await pumpWorkout(
        tester,
        WorkoutListItem(
          id: 1,
          type: WorkoutType.running,
          start: now.subtract(const Duration(hours: 1)),
          end: now.subtract(const Duration(minutes: 30)),
          utcOffset: Duration.zero,
          elapsed: const Duration(minutes: 30),
        ),
      );

      expect(
        labelOf(tester, WorkoutWidgetPreview.previewKey),
        allOf(contains('Running'), contains('08:00'), contains('30')),
      );
    });

    testWidgets('with no workout it invites one instead of inventing it', (
      tester,
    ) async {
      await pumpWorkout(tester, null);

      expect(find.text('Pick a workout and go'), findsOneWidget);
    });
  });

  testWidgets('the preview shows the chosen metrics from the snapshot', (
    tester,
  ) async {
    await pumpConfig(tester);

    expect(previewLabel(tester), contains('Sleep 6 h 52 min'));
    expect(previewLabel(tester), contains('Steps 2,224'));
    expect(find.text('synced 08:40'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('Limit of 3. Uncheck one to swap.'), findsOneWidget);
    expect(
      find.text('Preview in the app theme, dark right now'),
      findsOneWidget,
    );
  });

  testWidgets('a full selection ignores a fourth metric until one is removed', (
    tester,
  ) async {
    await pumpConfig(tester);

    await tester.tap(
      find.byKey(TodayWidgetConfigScreen.metricKey(WidgetMetric.spo2)),
    );
    await tester.pumpAndSettle();
    expect(previewLabel(tester), isNot(contains('SpO2')));

    await tester.tap(
      find.byKey(TodayWidgetConfigScreen.metricKey(WidgetMetric.sleep)),
    );
    await tester.pumpAndSettle();
    expect(find.text('You can pick 1 more.'), findsOneWidget);

    await tester.tap(
      find.byKey(TodayWidgetConfigScreen.metricKey(WidgetMetric.spo2)),
    );
    await tester.pumpAndSettle();
    expect(previewLabel(tester), contains('SpO2'));
    expect(previewLabel(tester), isNot(contains('Sleep')));
  });

  testWidgets('a theme override changes the preview note', (tester) async {
    await pumpConfig(tester);

    await reveal(
      tester,
      find.byKey(TodayWidgetConfigScreen.themeKey(WidgetTheme.light)),
    );
    await tester.tap(
      find.byKey(TodayWidgetConfigScreen.themeKey(WidgetTheme.light)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview in the light theme'), findsOneWidget);
  });

  testWidgets('adding the widget asks the launcher to pin the Today widget', (
    tester,
  ) async {
    final gateway = FakeWidgetGateway();
    await pumpConfig(tester, gateway: gateway);

    await reveal(tester, find.byKey(TodayWidgetConfigScreen.addKey));
    await tester.tap(find.byKey(TodayWidgetConfigScreen.addKey));
    await tester.pumpAndSettle();

    expect(gateway.pinned, [HomeWidgetKind.today]);
    expect(find.byKey(TodayWidgetConfigScreen.requestedKey), findsOneWidget);
    expect(find.text('Confirm on your home screen'), findsOneWidget);
  });

  testWidgets('with no metric the add button is disabled', (tester) async {
    await pumpConfig(tester, config: TodayWidgetConfig(metrics: const []));

    final button = tester.widget<FilledButton>(
      find.byKey(TodayWidgetConfigScreen.addKey),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('No metric chosen. Pick at least 1 below.'),
      findsOneWidget,
    );
  });

  testWidgets('stale, unpaired and empty states are spelled out', (
    tester,
  ) async {
    await pumpConfig(tester, scenario: offlineScenario);
    expect(find.textContaining('Not synced since'), findsOneWidget);

    await pumpConfig(
      tester,
      scenario: noDataScenario,
      gateway: FakeWidgetGateway(pinSupported: false),
    );
    expect(find.text('Pair a ring to fill this widget.'), findsOneWidget);
    expect(find.byKey(TodayWidgetConfigScreen.addKey), findsNothing);

    await pumpConfig(
      tester,
      scenario: MetricsScenario(nights: 0, activityDays: 0, ring: freshRing),
    );
    expect(
      find.text('No data yet. Keep the ring on and sync.'),
      findsOneWidget,
    );
  });
}
