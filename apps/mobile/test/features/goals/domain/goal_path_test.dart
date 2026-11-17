import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_path.dart';

Goal _goal({
  double? referenceKg = 74.0,
  LocalDate? blockStartedOn,
  GoalPace pace = GoalPace.standard,
}) {
  final start = blockStartedOn ?? const LocalDate(2026, 11, 16);
  return Goal(
    id: 1,
    kind: GoalKind.loseFat,
    pace: pace,
    startedOn: start,
    anchorKg: 78.4,
    referenceKg: referenceKg,
    blockStartedOn: start,
    blockAnchorKg: 78.4,
    phase: GoalPhase.block,
    phaseSince: start,
    phaseUntil: null,
    levers: const [],
    endedOn: null,
    endReason: null,
  );
}

const _rate = WeightRateReady(perWeek: -0.2958, low: -0.3881, high: -0.2034);

void main() {
  group('goalPathDay', () {
    test('is the Sunday before this Monday once the block is older', () {
      expect(
        goalPathDay(_goal(), const LocalDate(2026, 12, 10)),
        const LocalDate(2026, 12, 6),
      );
      expect(
        goalPathDay(_goal(), const LocalDate(2026, 12, 7)),
        const LocalDate(2026, 12, 6),
      );
    });

    test('is the block start when the block began after that Sunday', () {
      final goal = _goal(blockStartedOn: const LocalDate(2026, 12, 9));
      expect(
        goalPathDay(goal, const LocalDate(2026, 12, 10)),
        const LocalDate(2026, 12, 9),
      );
    });
  });

  group('goalPath', () {
    test('the prototype review reads on track with a March to May arrival', () {
      final path = goalPath(
        goal: _goal(),
        snapshot: (rate: _rate, trendKg: 77.782),
        heightCm: 178,
        on: const LocalDate(2026, 12, 7),
      );
      expect(path.state, PathState.onTrack);
      expect(path.targetPercent, 0.5);
      expect(path.capPercent, 0.5);
      expect(path.rate!.kg, closeTo(0.2958, 1e-9));
      expect(path.rate!.percent, closeTo(0.380, 0.001));
      expect(path.block!.end, const LocalDate(2027, 2, 7));
      expect(path.arrival!.earliest, const LocalDate(2027, 3, 13));
      expect(path.arrival!.latest, const LocalDate(2027, 5, 14));
      expect(path.overTheCap, isFalse);
    });

    test('no reference gives no arrival', () {
      final path = goalPath(
        goal: _goal(referenceKg: null),
        snapshot: (rate: _rate, trendKg: 77.782),
        heightCm: 178,
        on: const LocalDate(2026, 12, 7),
      );
      expect(path.arrival, isNull);
      expect(path.state, PathState.onTrack);
    });

    test('a building rate reads building with no arrival', () {
      final path = goalPath(
        goal: _goal(),
        snapshot: (
          rate: const WeightRateBuilding(daysMissing: 3, spanMissing: 0),
          trendKg: 77.9,
        ),
        heightCm: 178,
        on: const LocalDate(2026, 12, 7),
      );
      expect(path.rate, isNull);
      expect(path.state, PathState.building);
      expect(path.arrival, isNull);
    });

    test('a low end at or under zero hides the arrival', () {
      final path = goalPath(
        goal: _goal(),
        snapshot: (
          rate: const WeightRateReady(perWeek: -0.1, low: -0.3, high: 0.1),
          trendKg: 77.782,
        ),
        heightCm: 178,
        on: const LocalDate(2026, 12, 7),
      );
      expect(path.arrival, isNull);
    });

    test('a loss over the cap is above and over the cap', () {
      final path = goalPath(
        goal: _goal(),
        snapshot: (
          rate: const WeightRateReady(
            perWeek: -0.964,
            low: -1.082,
            high: -0.845,
          ),
          trendKg: 76.346,
        ),
        heightCm: 178,
        on: const LocalDate(2026, 12, 7),
      );
      expect(path.state, PathState.above);
      expect(path.overTheCap, isTrue);
    });

    test('the gentle pace halves the target', () {
      final path = goalPath(
        goal: _goal(pace: GoalPace.gentle),
        snapshot: (rate: _rate, trendKg: 77.782),
        heightCm: 178,
        on: const LocalDate(2026, 12, 7),
      );
      expect(path.targetPercent, 0.25);
      expect(path.block!.weeklyKg, closeTo(0.196, 1e-9));
    });

    test('a stale trend reads no trend and no arrival', () {
      final path = goalPath(
        goal: _goal(),
        snapshot: (rate: null, trendKg: null),
        heightCm: 178,
        on: const LocalDate(2026, 12, 7),
      );
      expect(path.trendKg, isNull);
      expect(path.state, PathState.building);
      expect(path.arrival, isNull);
    });
  });
}
