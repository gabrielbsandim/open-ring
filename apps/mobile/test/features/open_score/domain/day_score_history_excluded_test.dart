import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/metrics_fakes.dart';

DayScoreHistory _history() => DayScoreHistory(
  today: metricsToday,
  days: {
    metricsToday: day(),
    metricsToday.addDays(-1): day(),
    metricsToday.addDays(-2): day(),
    metricsToday.addDays(-3): day(sleepScore: 60),
    metricsToday.addDays(-4): day(sleepScore: 60),
  },
);

void main() {
  final weak = metricsToday.addDays(-3);

  test('without exclusions the average counts every closed full day', () {
    final average = _history().fullAverage(30);

    expect(average?.count, 4);
    expect(average?.value, 91);
  });

  test('an excluded date leaves the value and the count', () {
    final average = _history().fullAverage(30, excluded: {weak});

    expect(average?.count, 3);
    expect(average?.value, 92);
  });

  test('an empty exclusion set changes nothing', () {
    expect(
      // ignore: avoid_redundant_argument_values, the empty set is the case.
      _history().fullAverage(30, excluded: const {}),
      _history().fullAverage(30),
    );
  });

  test('excluding today or a date outside the window changes nothing', () {
    final outside = metricsToday.addDays(-90);

    expect(
      _history().fullAverage(30, excluded: {metricsToday, outside}),
      _history().fullAverage(30),
    );
  });

  test('excluding every closed full day leaves no average', () {
    final all = {for (var age = 1; age <= 4; age++) metricsToday.addDays(-age)};

    expect(_history().fullAverage(30, excluded: all), isNull);
  });

  test('on, scoredOn and scores ignore the exclusion', () {
    final history = _history()..fullAverage(30, excluded: {weak});

    expect(history.on(weak), isNotNull);
    expect(history.scoredOn(weak)?.value, 88);
    expect([for (final s in history.scores) s.date], contains(weak));
    expect(history.scores, hasLength(5));
  });
}
