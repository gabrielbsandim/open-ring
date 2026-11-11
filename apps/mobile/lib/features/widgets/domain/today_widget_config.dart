import 'package:meta/meta.dart';

enum WidgetMetric { readiness, sleep, steps, heartRate, spo2, stress, battery }

enum WidgetTheme { app, dark, light }

@immutable
final class TodayWidgetConfig {
  new({
    List<WidgetMetric> metrics = defaultMetrics,
    this.theme = WidgetTheme.app,
  }) : metrics = List.unmodifiable(metrics.toSet().take(maxMetrics));

  factory fromJson(Map<String, Object?> json) => TodayWidgetConfig(
    metrics: [
      for (final name in json['metrics'] as List? ?? const [])
        ?WidgetMetric.values.asNameMap()[name],
    ],
    theme: WidgetTheme.values.asNameMap()[json['theme']] ?? WidgetTheme.app,
  );

  static const maxMetrics = 3;

  static const List<WidgetMetric> defaultMetrics = [
    WidgetMetric.sleep,
    WidgetMetric.steps,
    WidgetMetric.heartRate,
  ];

  final List<WidgetMetric> metrics;
  final WidgetTheme theme;

  bool get isFull => metrics.length >= maxMetrics;

  bool get isEmpty => metrics.isEmpty;

  int get remaining => maxMetrics - metrics.length;

  bool contains(WidgetMetric metric) => metrics.contains(metric);

  bool canPick(WidgetMetric metric) => contains(metric) || !isFull;

  TodayWidgetConfig toggle(WidgetMetric metric) {
    if (contains(metric)) {
      return TodayWidgetConfig(
        metrics: [...metrics.where((m) => m != metric)],
        theme: theme,
      );
    }
    if (isFull) return this;
    return TodayWidgetConfig(metrics: [...metrics, metric], theme: theme);
  }

  TodayWidgetConfig withTheme(WidgetTheme value) =>
      TodayWidgetConfig(metrics: metrics, theme: value);

  Map<String, Object?> toJson() => {
    'metrics': [for (final m in metrics) m.name],
    'theme': theme.name,
  };

  @override
  bool operator ==(Object other) =>
      other is TodayWidgetConfig &&
      other.theme == theme &&
      other.metrics.length == metrics.length &&
      other.metrics.indexed.every((e) => metrics[e.$1] == e.$2);

  @override
  int get hashCode => Object.hash(theme, Object.hashAll(metrics));
}

abstract interface class TodayWidgetConfigStore {
  TodayWidgetConfig? read();

  Future<void> write(TodayWidgetConfig config);

  Future<void> reset();
}

final class InMemoryTodayWidgetConfigStore implements TodayWidgetConfigStore {
  new([this.saved]);

  TodayWidgetConfig? saved;

  @override
  TodayWidgetConfig? read() => saved;

  @override
  Future<void> write(TodayWidgetConfig config) async => saved = config;

  @override
  Future<void> reset() async => saved = null;
}
