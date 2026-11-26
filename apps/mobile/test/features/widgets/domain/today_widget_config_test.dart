import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';

void main() {
  test('defaults to sleep, steps and heart rate in the app theme', () {
    final config = TodayWidgetConfig();

    expect(config.metrics, TodayWidgetConfig.defaultMetrics);
    expect(config.theme, WidgetTheme.app);
    expect(config.isFull, isFalse);
    expect(config.remaining, 3);
  });

  test('metric metadata maps module ownership and ring requirement', () {
    expect(WidgetMetric.sleep.module, isNull);
    expect(WidgetMetric.dayScore.module, ModuleId.openScore);
    expect(WidgetMetric.weight.module, ModuleId.body);
    expect(WidgetMetric.energy.module, ModuleId.energy);
    expect(WidgetMetric.effort.module, ModuleId.effort);

    expect(WidgetMetric.weight.requiresRing, isFalse);
    for (final metric in WidgetMetric.values) {
      if (metric != WidgetMetric.weight) {
        expect(metric.requiresRing, isTrue, reason: metric.name);
      }
    }
  });

  test(
    'a full selection of 6 refuses a seventh metric until one is removed',
    () {
      var config = TodayWidgetConfig()
          .add(WidgetMetric.readiness)
          .add(WidgetMetric.spo2)
          .add(WidgetMetric.stress);

      expect(config.isFull, isTrue);
      expect(config.add(WidgetMetric.battery), same(config));
      expect(config.toggle(WidgetMetric.battery), same(config));
      expect(config.canPick(WidgetMetric.battery), isFalse);

      config = config.remove(WidgetMetric.sleep).add(WidgetMetric.battery);
      expect(config.metrics, [
        WidgetMetric.steps,
        WidgetMetric.heartRate,
        WidgetMetric.readiness,
        WidgetMetric.spo2,
        WidgetMetric.stress,
        WidgetMetric.battery,
      ]);
    },
  );

  test(
    'moveUp and moveDown reorder metrics and ignore out-of-bounds moves',
    () {
      final config = TodayWidgetConfig();

      expect(config.moveUp(0), same(config));
      expect(config.moveDown(2), same(config));
      expect(config.moveUp(3), same(config));
      expect(config.moveDown(-1), same(config));

      final movedUp = config.moveUp(2);
      expect(movedUp.metrics, [
        WidgetMetric.sleep,
        WidgetMetric.heartRate,
        WidgetMetric.steps,
      ]);

      final movedDown = movedUp.moveDown(0);
      expect(movedDown.metrics, [
        WidgetMetric.heartRate,
        WidgetMetric.sleep,
        WidgetMetric.steps,
      ]);
    },
  );

  test('removeForModule drops only metrics owned by that module', () {
    final config = TodayWidgetConfig(
      metrics: const [
        WidgetMetric.dayScore,
        WidgetMetric.steps,
        WidgetMetric.weight,
        WidgetMetric.energy,
        WidgetMetric.effort,
      ],
    );

    final updated = config.removeForModule(ModuleId.openScore);
    expect(updated.metrics, [
      WidgetMetric.steps,
      WidgetMetric.weight,
      WidgetMetric.energy,
      WidgetMetric.effort,
    ]);
    expect(updated.removeForModule(ModuleId.openScore), same(updated));

    final retained = updated.retainModules({ModuleId.body});
    expect(retained.metrics, [WidgetMetric.steps, WidgetMetric.weight]);
    expect(retained.retainModules({ModuleId.body}), same(retained));
  });

  test('effectiveMetrics filters disabled modules and hidden energy', () {
    final config = TodayWidgetConfig(
      metrics: const [
        WidgetMetric.dayScore,
        WidgetMetric.weight,
        WidgetMetric.energy,
        WidgetMetric.steps,
        WidgetMetric.effort,
      ],
    );

    expect(
      config.effectiveMetrics(
        enabled: {ModuleId.body, ModuleId.energy, ModuleId.openScore},
        hideNumbers: false,
      ),
      [
        WidgetMetric.dayScore,
        WidgetMetric.weight,
        WidgetMetric.energy,
        WidgetMetric.steps,
      ],
    );

    // Hiding numbers drops energy from effectiveMetrics without altering weight
    // or stored config.metrics, and restoring numbers brings energy back.
    expect(
      config.effectiveMetrics(
        enabled: {ModuleId.body, ModuleId.energy, ModuleId.openScore},
        hideNumbers: true,
      ),
      [WidgetMetric.dayScore, WidgetMetric.weight, WidgetMetric.steps],
    );
    expect(config.metrics, contains(WidgetMetric.energy));
  });

  test('json keeps order and theme, and drops unknown or extra metrics', () {
    final config = TodayWidgetConfig.fromJson(const {
      'metrics': [
        'dayScore',
        'unknown',
        'weight',
        'energy',
        'effort',
        'readiness',
        'stress',
        'sleep',
      ],
      'theme': 'dark',
    });

    expect(config.metrics, [
      WidgetMetric.dayScore,
      WidgetMetric.weight,
      WidgetMetric.energy,
      WidgetMetric.effort,
      WidgetMetric.readiness,
      WidgetMetric.stress,
    ]);
    expect(config.theme, WidgetTheme.dark);
    expect(TodayWidgetConfig.fromJson(config.toJson()), config);
    expect(TodayWidgetConfig.fromJson(const {}).theme, WidgetTheme.app);
  });
}
