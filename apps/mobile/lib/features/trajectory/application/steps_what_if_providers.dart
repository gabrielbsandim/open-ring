import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/trajectory/application/levers_providers.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/levers_view.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

sealed class WhatIfView {
  const new();
}

final class WhatIfOff extends WhatIfView {
  const new();
}

final class WhatIfRefused extends WhatIfView {
  const new(this.reason);

  final TrajectoryRefusal reason;
}

final class WhatIfNoSteps extends WhatIfView {
  const new(this.validDays);

  final int validDays;
}

/// A null [weight] means there is no weight scenario to add the steps to.
final class WhatIfReady extends WhatIfView {
  const new({
    required this.typical,
    required this.toSteps,
    required this.words,
    required this.clamped,
    required this.weight,
  });

  final int typical;
  final int toSteps;
  final CohortWords words;
  final bool clamped;
  final StepsWhatIf? weight;
}

final class WhatIfError extends WhatIfView {
  const new(this.error);

  final Object error;
}

final FutureProviderFamily<WhatIfView, int> whatIfProvider =
    FutureProvider.family<WhatIfView, int>((ref, extra) async {
      final view = await ref.watch(trajectoryViewProvider.future);
      switch (view) {
        case TrajectoryOff():
          return const WhatIfOff();
        case TrajectoryRefused(:final reason):
          return WhatIfRefused(reason);
        case TrajectoryError(:final error):
          return WhatIfError(error);
        case TrajectoryBuilding() || TrajectoryGuard() || TrajectoryReady():
          break;
      }
      try {
        return await _read(ref, view, extra);
      } on Object catch (error) {
        debugPrint('Steps what if could not be read: $error');
        return WhatIfError(error);
      }
    });

Future<WhatIfView> _read(Ref ref, TrajectoryView view, int extra) async {
  final levers = await ref.watch(leversProvider.future);
  return switch (levers) {
    LeversOff() => const WhatIfOff(),
    LeversError(:final error) => WhatIfError(error),
    LeversReady(:final levers) => await _ready(
      ref,
      view,
      extra,
      levers[RingLever.steps],
    ),
  };
}

Future<WhatIfView> _ready(
  Ref ref,
  TrajectoryView view,
  int extra,
  LeverReading? steps,
) async {
  final trend = steps?.trend;
  if (trend == null) return WhatIfNoSteps(steps?.validDays ?? 0);
  final typical = trend.typical.round();
  final toSteps = typical + extra;
  final percentLower =
      (1 - paluchHazard(toSteps) / paluchHazard(typical)) * 100;
  final weight = switch (view) {
    TrajectoryReady(:final trendKg) => stepsWhatIf(
      extraSteps: extra,
      typicalSteps: typical,
      kilograms: trendKg,
      centimeters: (await ref.watch(userProfileProvider.future))!
          .heightCentimeters!,
    ),
    _ => null,
  };
  return WhatIfReady(
    typical: typical,
    toSteps: toSteps,
    words: CohortWords.of(percentLower),
    clamped: toSteps > paluchAnchors.last.steps,
    weight: weight,
  );
}
