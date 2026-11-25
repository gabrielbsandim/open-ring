import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';

import '../../../helpers/layout_harness.dart';

const november = LocalDate(2026, 11, 10);
const december = LocalDate(2026, 12, 20);

const losing = WeightRateReady(perWeek: -0.35, low: -0.43, high: -0.26);
const stableRate = WeightRateReady(perWeek: 0.01, low: -0.1, high: 0.12);

WeightSummary summaryEnding(LocalDate asOf) {
  final daily = <DailyValue>[
    for (var age = 35; age >= 0; age--)
      (date: asOf.addDays(-age), value: 78.4 - (35 - age) * 0.03),
  ];
  return WeightSummary(
    last: WeighIn(
      id: 1,
      at: DateTime.utc(asOf.year, asOf.month, asOf.day, 8),
      offsetMinutes: 0,
      kilograms: daily.last.value,
      source: WeighInSource.manual,
    ),
    daily: daily,
    line: daily,
    rate: losing,
    noise: 0.35,
  );
}

TrajectoryReady readyView({
  LocalDate asOf = november,
  WeightRateReady rate = losing,
  double trendKg = 77.6,
  ScenarioBand? firm,
  ScenarioBand? band,
}) => TrajectoryReady(
  asOf: asOf,
  trendKg: trendKg,
  rate: rate,
  noiseKg: 0.35,
  firm: firm ?? const ScenarioBand(days: 28, low: 75.6, mid: 76.3, high: 76.95),
  band: band ?? const ScenarioBand(days: 84, low: 72.6, mid: 73.9, high: 75.1),
);

const guardView = TrajectoryGuard(
  LossRate(
    kg: 1.1,
    kgLow: 0.9,
    kgHigh: 1.3,
    percent: 1.4,
    percentLow: 1.2,
    percentHigh: 1.6,
  ),
);

List<Override> trajectoryOverrides({
  required TrajectoryView view,
  LocalDate asOf = november,
  UnitSystem units = UnitSystem.metric,
  bool hidden = false,
}) => [
  clockProvider.overrideWithValue(
    () => DateTime(asOf.year, asOf.month, asOf.day, 12),
  ),
  trajectoryViewProvider.overrideWith((ref) async => view),
  weightSummaryProvider.overrideWith((ref) async => summaryEnding(asOf)),
  unitSystemStoreProvider.overrideWithValue(InMemoryUnitSystemStore(units)),
  hideNumbersStoreProvider.overrideWithValue(
    InMemoryHideNumbersStore(hidden: hidden),
  ),
];

Future<void> pumpTrajectory(
  WidgetTester tester, {
  required TrajectoryView view,
  LocalDate asOf = november,
  UnitSystem units = UnitSystem.metric,
  bool hidden = false,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
}) => pumpScaled(
  tester,
  screenHost(const TrajectoryScreen()),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: locale,
  overrides: trajectoryOverrides(
    view: view,
    asOf: asOf,
    units: units,
    hidden: hidden,
  ),
);
