import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';

const levelAccountDays = 28;
const levelAccountShort = 7;

enum LevelMove { up, down, same }

/// The Level over the closed days of [history]: today is still moving, so it
/// enters only once it has closed.
LevelTrack closedLevelTrack(DayScoreHistory history, Set<LocalDate> excluded) =>
    levelTrack([
      for (final date in history.dates)
        if (date != history.today)
          LevelDay(
            date: date,
            score: history.scoredOn(date)?.value,
            excluded: excluded.contains(date),
          ),
    ]);

// Compared at the one decimal the screens show.
LevelMove levelMove(double before, double after) {
  final from = (before * 10).round();
  final to = (after * 10).round();
  if (to > from) return LevelMove.up;
  if (to < from) return LevelMove.down;
  return LevelMove.same;
}

/// The steps of the last [days] closed days, newest first.
List<LevelStep> levelAccount(LevelTrack track, {int days = levelAccountDays}) {
  final steps = track.steps;
  final from = steps.length > days ? steps.length - days : 0;
  return steps.sublist(from).reversed.toList();
}
