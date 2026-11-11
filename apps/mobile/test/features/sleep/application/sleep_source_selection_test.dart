import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/sleep/application/sleep_source_selection.dart';

import '../../../helpers/metrics_fakes.dart';

const _watch = 'com.garmin.android.apps.connectmobile';

// Same 23:18 to 06:42 window as the ring night, all light: 7h24 asleep.
List<SleepSpan> _watchNight(LocalDate date) {
  final start = nightStart(date);
  return [
    SleepSpan(
      start: start,
      end: start.add(const Duration(minutes: 444)),
      phase: SleepPhase.light,
      utcOffset: Duration.zero,
    ),
  ];
}

void main() {
  final yesterday = metricsToday.addDays(-1);
  final spans = {
    ringSource: nightSpans(metricsToday),
    _watch: [..._watchNight(metricsToday), ..._watchNight(yesterday)],
  };

  test('the ring wins a date both measured, without adding them', () {
    final nights = nightsBySourcePriority(spans, const [ringSource, _watch]);

    expect(nights[metricsToday]!.asleep, const Duration(minutes: 412));
    expect(nights[metricsToday]!.timeIn(SleepPhase.rem), isNot(Duration.zero));
  });

  test('a lower source fills a date the ring missed', () {
    final nights = nightsBySourcePriority(spans, const [ringSource, _watch]);

    expect(nights.keys, [yesterday, metricsToday]);
    expect(nights[yesterday]!.asleep, const Duration(minutes: 444));
  });

  test('putting the watch first takes its night instead', () {
    final nights = nightsBySourcePriority(spans, const [_watch, ringSource]);

    expect(nights[metricsToday]!.asleep, const Duration(minutes: 444));
    expect(nights[metricsToday]!.timeIn(SleepPhase.rem), Duration.zero);
  });

  test('a source missing from the order is ignored', () {
    final nights = nightsBySourcePriority(spans, const [ringSource]);

    expect(nights.keys, [metricsToday]);
  });
}
