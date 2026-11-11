import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/heart/presentation/heart_labels.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/metrics_pump.dart';

Future<void> pick(WidgetTester tester, HeartMetric metric) async {
  await tester.tap(find.byKey(HeartScreen.metricKey(metric)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without readings it says what to do', (tester) async {
    await pumpMetrics(tester, screenHost(const HeartScreen()), noDataScenario);

    expect(find.textContaining('after the first sync'), findsOneWidget);
    expect(find.byKey(HeartScreen.emptyActionKey), findsOneWidget);
    expect(find.byKey(HeartScreen.chartKey), findsNothing);
  });

  testWidgets('opens on heart rate with resting HR against baseline', (
    tester,
  ) async {
    await pumpMetrics(
      tester,
      screenHost(const HeartScreen()),
      fullDataScenario,
    );

    expect(find.text('Today until 09:00'), findsOneWidget);
    expect(find.byKey(HeartScreen.chartKey), findsOneWidget);
    expect(find.text('Resting heart rate: 58 bpm'), findsOneWidget);
    expect(find.textContaining('bpm against your baseline of'), findsOneWidget);
  });

  testWidgets('HRV compares last night with the typical value', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const HeartScreen()),
      fullDataScenario,
    );

    await pick(tester, HeartMetric.hrv);

    expect(find.text('Overnight HRV: 46 ms'), findsOneWidget);
    expect(find.textContaining('against your typical'), findsOneWidget);
  });

  testWidgets('SpO2 summarises last night', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const HeartScreen()),
      fullDataScenario,
    );

    await pick(tester, HeartMetric.spo2);

    expect(find.text('Last night'), findsOneWidget);
    expect(
      find.textContaining('lowest 89%. 1 hourly reading below 90%.'),
      findsOneWidget,
    );
  });

  testWidgets('stress shows the time in each band', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const HeartScreen()),
      fullDataScenario,
    );

    await pick(tester, HeartMetric.stress);

    expect(find.text('Rest (1 to 25)'), findsOneWidget);
    expect(find.text('High (76 to 100)'), findsOneWidget);
    expect(find.textContaining('from 20 to 78'), findsOneWidget);
  });
}
