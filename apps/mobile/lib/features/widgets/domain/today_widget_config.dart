import 'package:meta/meta.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

enum WidgetMetric {
  readiness,
  sleep,
  steps,
  heartRate,
  spo2,
  stress,
  battery,
  dayScore(module: ModuleId.openScore),
  weight(module: ModuleId.body, requiresRing: false),
  energy(module: ModuleId.energy),
  effort(module: ModuleId.effort);

  new({this.module, this.requiresRing = true});

  final ModuleId? module;
  final bool requiresRing;
}

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

  static const maxMetrics = 6;

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

  TodayWidgetConfig add(WidgetMetric metric) {
    if (contains(metric) || isFull) return this;
    return TodayWidgetConfig(metrics: [...metrics, metric], theme: theme);
  }

  TodayWidgetConfig remove(WidgetMetric metric) {
    if (!contains(metric)) return this;
    return TodayWidgetConfig(
      metrics: [...metrics.where((m) => m != metric)],
      theme: theme,
    );
  }

  TodayWidgetConfig toggle(WidgetMetric metric) =>
      contains(metric) ? remove(metric) : add(metric);

  TodayWidgetConfig moveUp(int index) {
    if (index <= 0 || index >= metrics.length) return this;
    return _swap(index - 1, index);
  }

  TodayWidgetConfig moveDown(int index) {
    if (index < 0 || index >= metrics.length - 1) return this;
    return _swap(index, index + 1);
  }

  TodayWidgetConfig _swap(int first, int second) {
    final next = [...metrics];
    final held = next[first];
    next[first] = next[second];
    next[second] = held;
    return TodayWidgetConfig(metrics: next, theme: theme);
  }

  TodayWidgetConfig removeForModule(ModuleId id) {
    if (!metrics.any((metric) => metric.module == id)) return this;
    return TodayWidgetConfig(
      metrics: [
        for (final metric in metrics)
          if (metric.module != id) metric,
      ],
      theme: theme,
    );
  }

  TodayWidgetConfig retainModules(Set<ModuleId> enabled) {
    final keep = [
      for (final metric in metrics)
        if (metric.module == null || enabled.contains(metric.module)) metric,
    ];
    if (keep.length == metrics.length) return this;
    return TodayWidgetConfig(metrics: keep, theme: theme);
  }

  List<WidgetMetric> effectiveMetrics({
    required Set<ModuleId> enabled,
    required bool hideNumbers,
  }) => [
    for (final metric in metrics)
      if (_isVisible(metric, enabled: enabled, hideNumbers: hideNumbers))
        metric,
  ];

  bool _isVisible(
    WidgetMetric metric, {
    required Set<ModuleId> enabled,
    required bool hideNumbers,
  }) {
    final owner = metric.module;
    if (owner != null && !enabled.contains(owner)) return false;
    if (metric == WidgetMetric.energy && hideNumbers) return false;
    return true;
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
