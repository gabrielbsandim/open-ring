import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';
import 'package:open_ring/features/trends/presentation/trends_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/metrics_pump.dart';

final _stepsOnly = MetricsScenario(nights: 0, activityDays: 5, ring: freshRing);

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _pick(
  WidgetTester tester, {
  TrendMetric? metric,
  TrendRange? range,
}) async {
  if (metric != null) await _tap(tester, TrendsKeys.metric(metric));
  if (range != null) await _tap(tester, TrendsKeys.range(range));
}

void main() {
  testWidgets('without data it says what to do', (tester) async {
    await pumpMetrics(tester, screenHost(const TrendsScreen()), noDataScenario);

    expect(find.textContaining('after the first sync'), findsOneWidget);
    expect(find.byKey(TrendsKeys.emptyAction), findsOneWidget);
    expect(find.byKey(TrendsKeys.chart), findsNothing);
  });

  testWidgets('opens on resting HR over 30 days with average and range', (
    tester,
  ) async {
    await pumpMetrics(
      tester,
      screenHost(const TrendsScreen()),
      fullDataScenario,
    );

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Resting HR · 30 days'), findsOneWidget);
    expect(find.byKey(TrendsKeys.summary), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Values on 28 of 30 days.'), findsOneWidget);
    expect(find.textContaining('inside your range'), findsOneWidget);
    expect(find.textContaining('your range '), findsWidgets);
    expect(find.text('Last night: 58 bpm.'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('steps leave today out of the average and say so', (
    tester,
  ) async {
    await pumpMetrics(
      tester,
      screenHost(const TrendsScreen()),
      fullDataScenario,
    );

    await _pick(tester, metric: TrendMetric.steps, range: TrendRange.week);

    expect(find.text('Steps · 7 days'), findsOneWidget);
    expect(find.text('Today so far: 2,224 steps.'), findsOneWidget);
    expect(find.text('Values on 6 of 7 days.'), findsOneWidget);
    expect(find.textContaining('stays out of the average'), findsOneWidget);
    expect(find.textContaining('inside your range'), findsNothing);
  });

  testWidgets('sleep shows the time asleep per night', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const TrendsScreen()),
      fullDataScenario,
    );

    await _pick(tester, metric: TrendMetric.sleepDuration);

    expect(find.text('asleep on average'), findsOneWidget);
    expect(find.textContaining('Last night: 6 h'), findsOneWidget);
  });

  testWidgets('a metric without values in the range says what to do', (
    tester,
  ) async {
    await pumpMetrics(tester, screenHost(const TrendsScreen()), _stepsOnly);

    expect(find.byKey(TrendsKeys.metricEmpty), findsOneWidget);
    expect(find.textContaining('Wear the ring to bed'), findsOneWidget);
    expect(find.byKey(TrendsKeys.summary), findsNothing);

    await _pick(tester, metric: TrendMetric.steps);

    expect(find.byKey(TrendsKeys.metricEmpty), findsNothing);
    expect(find.byKey(TrendsKeys.summary), findsOneWidget);
    expect(
      find.text(
        'Not enough days yet to compare the first and second half of the '
        'range.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Heart opens History inside its tab', (tester) async {
    await pumpMetrics(tester, const OpenRingApp(), fullDataScenario);

    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.heart)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(HeartScreen.trendsKey),
      300,
      scrollable: find
          .descendant(
            of: find.byType(HeartScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _tap(tester, HeartScreen.trendsKey);

    expect(find.byType(TrendsScreen), findsOneWidget);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });

  group('layout', () {
    final cases = <String, (MetricsScenario, TrendMetric?, TrendRange?)>{
      'resting HR over 30 days': (fullDataScenario, null, null),
      'steps over 90 days': (
        fullDataScenario,
        TrendMetric.steps,
        TrendRange.quarter,
      ),
      'sleep over 7 days': (
        fullDataScenario,
        TrendMetric.sleepDuration,
        TrendRange.week,
      ),
      'a metric without values': (_stepsOnly, null, null),
      'no data': (noDataScenario, null, null),
    };
    for (final layout in layoutMatrix()) {
      for (final MapEntry(key: name, value: (scenario, metric, range))
          in cases.entries) {
        testWidgets('$name at $layout', (tester) async {
          await pumpScaled(
            tester,
            screenHost(const TrendsScreen()),
            textScaler: layout.textScaler,
            brightness: layout.brightness,
            locale: layout.locale,
            overrides: metricsOverrides(scenario),
          );
          await expectNoLayoutOverflow(
            () => _pick(tester, metric: metric, range: range),
          );

          expect(find.byType(TrendsScreen), findsOneWidget);
        });
      }
    }
  });
}
