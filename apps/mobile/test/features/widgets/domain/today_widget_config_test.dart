import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';

void main() {
  test('defaults to sleep, steps and heart rate in the app theme', () {
    final config = TodayWidgetConfig();

    expect(config.metrics, TodayWidgetConfig.defaultMetrics);
    expect(config.theme, WidgetTheme.app);
    expect(config.isFull, isTrue);
  });

  test('a full selection refuses a fourth metric until one is removed', () {
    final config = TodayWidgetConfig();

    expect(config.toggle(WidgetMetric.spo2), same(config));
    expect(config.canPick(WidgetMetric.spo2), isFalse);
    final swapped = config.toggle(WidgetMetric.sleep).toggle(WidgetMetric.spo2);
    expect(swapped.metrics, [
      WidgetMetric.steps,
      WidgetMetric.heartRate,
      WidgetMetric.spo2,
    ]);
  });

  test('json keeps order and theme, and drops unknown or extra metrics', () {
    final config = TodayWidgetConfig.fromJson(const {
      'metrics': ['battery', 'unknown', 'readiness', 'stress', 'sleep'],
      'theme': 'dark',
    });

    expect(config.metrics, [
      WidgetMetric.battery,
      WidgetMetric.readiness,
      WidgetMetric.stress,
    ]);
    expect(config.theme, WidgetTheme.dark);
    expect(TodayWidgetConfig.fromJson(config.toJson()), config);
    expect(TodayWidgetConfig.fromJson(const {}).theme, WidgetTheme.app);
  });
}
