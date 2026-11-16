import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal.dart';

import 'goal_fixtures.dart';

const draftD = GoalDraft(
  kind: GoalKind.loseFat,
  pace: GoalPace.standard,
  startedOn: LocalDate(2026, 11, 16),
  anchorKg: 78.4,
  referenceKg: 74.0,
  levers: [strengthLever],
);
