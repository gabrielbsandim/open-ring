import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/level_view.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/metrics_fakes.dart';

void main() {
  test('today stays out of the track until it closes', () {
    final history = mixedHistory();
    final track = closedLevelTrack(history, const {});

    expect(track.steps.length, history.dates.length - 1);
    expect(track.on(metricsToday), isNull);
    expect(track.steps.last.date, metricsToday.addDays(-1));
  });

  test('a tagged day and a day without a score leave the Level where it '
      'was', () {
    final history = mixedHistory();
    final weak = metricsToday.addDays(-3);
    final blank = metricsToday.addDays(-2);
    final plain = closedLevelTrack(history, const {});
    final tagged = closedLevelTrack(history, {weak});

    expect(plain.on(weak)!.effect, isNotNull);
    expect(plain.on(blank)!.effect, isNull);
    expect(plain.on(blank)!.after, plain.on(blank)!.before);
    expect(tagged.on(weak)!.effect, isNull);
    expect(tagged.on(weak)!.after, tagged.on(weak)!.before);
    expect(tagged.level, isNot(plain.level));
  });

  test('with fewer than the seed days there is no Level yet', () {
    final track = closedLevelTrack(mixedHistory(days: levelSeedDays), const {});

    expect(track.level, isNull);
    expect(track.counted, levelSeedDays - 2);
    expect(track.missing, 2);
  });

  test('a move is read at one decimal', () {
    expect(levelMove(78.42, 78.44), LevelMove.same);
    expect(levelMove(78.44, 78.46), LevelMove.up);
    expect(levelMove(78.46, 78.44), LevelMove.down);
  });

  test('the account lists the newest closed days first', () {
    final track = closedLevelTrack(mixedHistory(), const {});
    final rows = levelAccount(track);

    expect(rows.length, levelAccountDays);
    expect(rows.first.date, metricsToday.addDays(-1));
    expect(rows.last.date, metricsToday.addDays(-levelAccountDays));
    expect(levelAccount(track, days: 500).length, track.steps.length);
  });

  test('each bar gets the line its day had to pass', () {
    final track = closedLevelTrack(mixedHistory(), const {});
    final lines = levelLines(track, today: metricsToday, days: 30);

    expect(lines.length, 30);
    expect(lines.last, track.level);
    expect(lines[28], track.lineOn(metricsToday.addDays(-1)));
    expect(lines.first, track.lineOn(metricsToday.addDays(-29)));
    expect(lines.where((line) => line == null).length, 4);
  });

  test('before the Level exists no bar has a line', () {
    final track = closedLevelTrack(mixedHistory(days: 10), const {});

    expect(
      levelLines(track, today: metricsToday, days: 30),
      everyElement(isNull),
    );
  });
}
