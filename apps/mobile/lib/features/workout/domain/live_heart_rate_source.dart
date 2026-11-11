enum HeartRateProblem { noRing, busy, unreachable }

final class HeartRateUnavailable implements Exception {
  const new(this.problem);

  final HeartRateProblem problem;

  @override
  String toString() => 'HeartRateUnavailable(${problem.name})';
}

abstract interface class LiveHeartRateSource {
  Stream<int> bpm();
}
