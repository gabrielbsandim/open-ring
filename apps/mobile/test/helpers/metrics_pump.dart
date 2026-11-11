import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';
import 'metrics_fakes.dart';

Future<void> pumpMetrics(
  WidgetTester tester,
  Widget widget,
  MetricsScenario scenario, {
  Locale locale = const Locale('en'),
}) => pumpScaled(
  tester,
  widget,
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: locale,
  overrides: metricsOverrides(scenario),
);
