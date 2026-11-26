import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/trajectory/application/levers_providers.dart';
import 'package:open_ring/features/trajectory/domain/levers_view.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

import '../presentation/trajectory_screen_fixtures.dart';

LeverTrend stepsTrend(double typical) => LeverTrend(
  slopePerDay: 0,
  slopeLow: -1,
  slopeHigh: 1,
  typical: typical,
  centerDay: 45,
  validDays: 80,
);

LeversReady leversWith({LeverTrend? trend, int validDays = 80}) =>
    LeversReady({RingLever.steps: (validDays: validDays, trend: trend)});

List<Override> whatIfOverrides({
  TrajectoryView? view,
  double typical = 8700,
  LeversView? levers,
  double? height = 178,
  bool hidden = false,
  EnergyGate gate = EnergyGate.on,
  bool withProfile = true,
  Future<List<WeighIn>> Function()? weighIns,
  Future<TrajectoryView> Function(Ref ref)? read,
}) => [
  ...trajectoryOverrides(
    view: view ?? readyView(),
    hidden: hidden,
    weighIns: weighIns,
    read: read,
  ),
  leversProvider.overrideWith(
    (ref) async => levers ?? leversWith(trend: stepsTrend(typical)),
  ),
  if (withProfile)
    userProfileStoreProvider.overrideWithValue(
      InMemoryUserProfileStore(UserProfile(heightCentimeters: height)),
    ),
  energyGateProvider.overrideWithValue(gate),
];
