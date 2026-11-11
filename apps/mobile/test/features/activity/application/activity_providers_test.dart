import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/activity_view.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';

import '../../../helpers/metrics_fakes.dart';

ActivitySlot _slot(
  DateTime start,
  int steps, {
  Duration offset = Duration.zero,
}) => ActivitySlot(
  start: start,
  utcOffset: offset,
  duration: const Duration(minutes: 15),
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

void main() {
  group('hourlySteps', () {
    test('adds slots into the local hour of their own offset', () {
      final hours = hourlySteps(metricsToday, [
        _slot(DateTime.utc(2026, 11, 10, 7), 100),
        _slot(DateTime.utc(2026, 11, 10, 7, 15), 50),
        _slot(
          DateTime.utc(2026, 11, 10, 5),
          30,
          offset: const Duration(hours: 3),
        ),
        _slot(DateTime.utc(2026, 11, 9, 23), 999),
      ]);

      expect(hours, hasLength(24));
      expect(hours[7], 150);
      expect(hours[8], 30);
      expect(hours[23], isNull);
      expect(hours.whereType<int>().fold<int>(0, (a, b) => a + b), 180);
    });
  });

  group('ActivityDayView', () {
    ActivityDayView view({DailyActivity? today, List<int?>? hours}) =>
        ActivityDayView(
          date: metricsToday,
          stepGoal: 8000,
          today: today,
          hourlySteps: hours ?? List.filled(24, null),
          week: [(date: metricsToday, activity: today)],
        );

    test('the peak is the first hour with the most steps', () {
      final hours = List<int?>.filled(24, 0);
      hours[9] = 300;
      hours[18] = 620;
      hours[19] = 620;

      expect(view(hours: hours).peak, (hour: 18, steps: 620));
    });

    test('no steps means no peak and an empty view', () {
      expect(view().peak, isNull);
      expect(view().isEmpty, isTrue);
      expect(view().goalShare, 0);
    });

    test('the goal share can pass one', () {
      const today = DailyActivity(
        date: metricsToday,
        steps: 12000,
        activeKilocalories: 400,
        distanceMeters: 9000,
      );

      expect(view(today: today).goalShare, 1.5);
      expect(view(today: today).isEmpty, isFalse);
    });
  });

  group('activityDayProvider', () {
    ProviderContainer container(MetricsScenario scenario) {
      final c = ProviderContainer(overrides: scenario.overrides());
      addTearDown(c.dispose);
      return c;
    }

    test('builds today, the hourly bars and seven days oldest first', () async {
      final c = container(fullDataScenario);

      final view = await c.read(activityDayProvider.future);

      expect(view.today?.steps, 2224);
      expect(view.hourlySteps[18], 620);
      expect(view.week, hasLength(activityWeekDays));
      expect(view.week.first.date, metricsToday.addDays(-6));
      expect(view.week.last.date, metricsToday);
      expect(view.week.every((d) => d.activity != null), isTrue);
    });

    test('without data the view is empty', () async {
      final view = await container(noDataScenario)
          .read(activityDayProvider.future);

      expect(view.isEmpty, isTrue);
      expect(view.hourlySteps.every((h) => h == null), isTrue);
    });

    test('a new data revision reads the reader again', () async {
      final c = container(fullDataScenario);
      final first = await c.read(activityDayProvider.future);

      c.read(dataRevisionProvider.notifier).bump();
      final second = await c.read(activityDayProvider.future);

      expect(identical(first, second), isFalse);
      expect(second.today?.steps, 2224);
    });
  });

  test('LocalDate of a slot uses its offset', () {
    final slot = _slot(
      DateTime.utc(2026, 11, 9, 23),
      1,
      offset: const Duration(hours: 2),
    );

    expect(slot.date, const LocalDate(2026, 11, 10));
    expect(slot.localHour, 1);
  });
}
