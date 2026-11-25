import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const november = LocalDate(2026, 11, 10);
const december = LocalDate(2026, 12, 20);

const trajectoryStub = 'trajectory stub';
const settingsStub = 'settings stub';

const losing = WeightRateReady(perWeek: -0.35, low: -0.43, high: -0.26);
const stableRate = WeightRateReady(perWeek: 0.01, low: -0.1, high: 0.12);

WeightSummary summaryEnding(LocalDate asOf) =>
    summaryOn([for (var age = 35; age >= 0; age--) asOf.addDays(-age)]);

WeightSummary summaryOn(List<LocalDate> dates) {
  final daily = <DailyValue>[
    for (final (i, date) in dates.indexed) (date: date, value: 78.4 - i * 0.03),
  ];
  final asOf = dates.last;
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
  Future<TrajectoryView> Function()? load,
  Future<WeightSummary?> Function()? summaryLoad,
  Future<List<WeighIn>> Function()? weighIns,
}) => [
  clockProvider.overrideWithValue(
    () => DateTime(asOf.year, asOf.month, asOf.day, 12),
  ),
  trajectoryViewProvider.overrideWith(
    (ref) => load?.call() ?? Future.value(view),
  ),
  weighInsProvider.overrideWith(
    (ref) => weighIns?.call() ?? Future.value(const <WeighIn>[]),
  ),
  weightSummaryProvider.overrideWith((ref) async {
    await ref.watch(weighInsProvider.future);
    return summaryLoad == null ? summaryEnding(asOf) : await summaryLoad();
  }),
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
  Future<TrajectoryView> Function()? load,
  Future<WeightSummary?> Function()? summaryLoad,
  Future<List<WeighIn>> Function()? weighIns,
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
    load: load,
    summaryLoad: summaryLoad,
    weighIns: weighIns,
  ),
);

GoRouter stubRouter(Widget home) => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(
      path: AppPaths.trajectory,
      builder: (_, _) => const Scaffold(body: Text(trajectoryStub)),
    ),
    GoRoute(
      path: AppPaths.settings,
      builder: (_, _) => const Scaffold(body: Text(settingsStub)),
    ),
  ],
);

Widget routerHost(GoRouter router) => MaterialApp.router(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  localeListResolutionCallback: AppLocales.resolve,
  supportedLocales: AppLocales.supported,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  routerConfig: router,
);

Future<GoRouter> pumpTrajectoryRouted(
  WidgetTester tester, {
  required TrajectoryView view,
}) async {
  final router = stubRouter(const TrajectoryScreen());
  await pumpScaled(
    tester,
    routerHost(router),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.light,
    locale: const Locale('en'),
    overrides: trajectoryOverrides(view: view),
  );
  return router;
}
