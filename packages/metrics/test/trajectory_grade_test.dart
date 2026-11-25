import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

import 'trajectory_series.dart';

const _oct26 = LocalDate(2026, 10, 26);
const _nov02 = LocalDate(2026, 11, 2);

void main() {
  final change = prototypeSeries(0.05);
  final fast = prototypeSeries(0.16);

  group('the enum', () {
    test('has below, inside and above', () {
      expect(ProjectionGrade.values, [
        ProjectionGrade.below,
        ProjectionGrade.inside,
        ProjectionGrade.above,
      ]);
    });
  });

  group('6. grading the prototype projections', () {
    test('2026-10-26 on the change series is inside, 78.301', () {
      final result = gradeProjection(
        monday: _oct26,
        low: 77.058,
        high: 79.762,
        today: seriesToday,
        weighIns: change,
      );
      expect(result, isNotNull);
      expect(result!.grade, ProjectionGrade.inside);
      expect(result.actualKg, closeTo(78.301, 0.001));
    });

    test('2026-11-02 on the fast series is below, 77.285', () {
      final result = gradeProjection(
        monday: _nov02,
        low: 77.439,
        high: 79.102,
        today: seriesToday,
        weighIns: fast,
      );
      expect(result, isNotNull);
      expect(result!.grade, ProjectionGrade.below);
      expect(result.actualKg, closeTo(77.285, 0.001));
    });

    test('a synthetic band of 70 to 71 is above', () {
      final result = gradeProjection(
        monday: _oct26,
        low: 70,
        high: 71,
        today: seriesToday,
        weighIns: change,
      );
      expect(result, isNotNull);
      expect(result!.grade, ProjectionGrade.above);
      expect(result.actualKg, closeTo(78.301, 0.001));
    });

    test('today 2026-11-22 is null, the due date is 11-23', () {
      final result = gradeProjection(
        monday: _oct26,
        low: 77.058,
        high: 79.762,
        today: const LocalDate(2026, 11, 22),
        weighIns: change,
      );
      expect(result, isNull);
    });
  });

  group('the due date is monday plus 28', () {
    final due = _oct26.addDays(28);

    ({ProjectionGrade grade, double actualKg})? gradeOn(
      LocalDate today,
      List<DailyValue> weighIns,
    ) => gradeProjection(
      monday: _oct26,
      low: 77,
      high: 79,
      today: today,
      weighIns: weighIns,
    );

    test('the day before it is null even with weigh-ins', () {
      expect(gradeOn(due.addDays(-1), change), isNull);
    });

    test('the due day itself grades', () {
      expect(gradeOn(due, change), isNotNull);
    });

    test('weigh-ins only after the due date give null', () {
      final late = [(date: due.addDays(1), value: 78.0)];
      expect(gradeOn(due.addDays(2), late), isNull);
    });

    test('no weigh-ins at all give null', () {
      expect(gradeOn(due, const []), isNull);
    });

    test('a weigh-in after the due date does not move the actual', () {
      final withLater = [
        (date: due, value: 78.0),
        (date: due.addDays(1), value: 90.0),
      ];
      final result = gradeOn(due.addDays(5), withLater);
      expect(result, isNotNull);
      expect(result!.actualKg, closeTo(78, 1e-9));
    });
  });

  group('band ends count inside', () {
    final due = _oct26.addDays(28);
    final single = [(date: due, value: 70.0)];

    ProjectionGrade? gradeBand(double low, double high) => gradeProjection(
      monday: _oct26,
      low: low,
      high: high,
      today: due,
      weighIns: single,
    )?.grade;

    test('actual equal to low is inside', () {
      expect(gradeBand(70, 71), ProjectionGrade.inside);
    });

    test('actual equal to high is inside', () {
      expect(gradeBand(69, 70), ProjectionGrade.inside);
    });

    test('just over low is below', () {
      expect(gradeBand(70.0001, 71), ProjectionGrade.below);
    });

    test('just under high is above', () {
      expect(gradeBand(69, 69.9999), ProjectionGrade.above);
    });
  });

  group('the due date falls on a skipped weigh-in day', () {
    test('the actual is the trend at the last weigh-in before it', () {
      final monday = seriesStart.addDays(-23);
      final due = monday.addDays(28);
      expect(due, seriesStart.addDays(5));
      final before = [
        for (final day in change)
          if (day.date.compareTo(due) <= 0) day,
      ];
      expect(before.last.date, seriesStart.addDays(4));
      final result = gradeProjection(
        monday: monday,
        low: 70,
        high: 90,
        today: seriesToday,
        weighIns: change,
      );
      expect(result, isNotNull);
      expect(result!.grade, ProjectionGrade.inside);
      expect(result.actualKg, closeTo(weightTrend(before).last.value, 1e-9));
    });
  });
}
