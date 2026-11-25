import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/application/food_energy.dart';
import 'package:open_ring/features/goals/domain/goal.dart';

const _started = LocalDate(2026, 11, 1);

Goal _goal({
  GoalPhase phase = GoalPhase.block,
  double? blockAnchorKg = 80,
  LocalDate blockStartedOn = _started,
}) => Goal(
  id: 1,
  kind: GoalKind.loseFat,
  pace: null,
  startedOn: _started,
  anchorKg: 80,
  referenceKg: null,
  blockStartedOn: blockStartedOn,
  blockAnchorKg: blockAnchorKg,
  phase: phase,
  phaseSince: _started,
  phaseUntil: null,
  levers: const [],
  endedOn: null,
  endReason: null,
);

void main() {
  group('TR10a interface: energyBlockStart is public and keeps its rules', () {
    test('a block with an anchor gives the day the block started', () {
      const day = LocalDate(2026, 11, 5);
      expect(energyBlockStart(_goal(blockStartedOn: day)), day);
    });

    test('no goal gives null', () {
      expect(energyBlockStart(null), isNull);
    });

    for (final phase in [
      GoalPhase.maintenance,
      GoalPhase.paused,
      GoalPhase.ended,
    ]) {
      test('${phase.name} gives null even with a recent block start', () {
        expect(energyBlockStart(_goal(phase: phase)), isNull);
      });
    }

    test('a block without an anchor weight gives null', () {
      expect(energyBlockStart(_goal(blockAnchorKg: null)), isNull);
    });
  });
}
