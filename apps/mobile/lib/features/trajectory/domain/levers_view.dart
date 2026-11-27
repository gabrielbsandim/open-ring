import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';

typedef LeverReading = ({int validDays, LeverTrend? trend});

@immutable
sealed class LeversView {
  const new();
}

final class LeversOff extends LeversView {
  const new();
}

final class LeversReady extends LeversView {
  new(Map<RingLever, LeverReading> levers) : levers = Map.unmodifiable(levers);

  final Map<RingLever, LeverReading> levers;
}

final class LeversError extends LeversView {
  const new(this.error);

  final Object error;
}
