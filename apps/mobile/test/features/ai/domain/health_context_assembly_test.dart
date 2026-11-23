import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

const _today = LocalDate(2026, 11, 10);

AiContextSources _sources({int stepDays = 0, AiFoodSummary? food}) =>
    AiContextSources(
      today: _today,
      replyLanguage: 'en',
      units: const AiUnits(),
      profile: const AiProfileInput(stepGoal: 8000),
      hasRing: true,
      importedIncluded: false,
      food: food,
      series: {
        AiDailyMetric.steps: {
          for (var age = 0; age < stepDays; age++)
            _today.addDays(-age): 5000.0 + age,
        },
      },
    );

HealthContextInput _assemble(AiContextSources s) => assembleHealthContextInput(
  s,
  detail: AiDetailLevel.standard,
  window: AiContextWindow.standard,
);

void main() {
  test('one row per calendar day, oldest first, empty days kept', () {
    final input = _assemble(_sources(stepDays: 2));

    expect(input.days, hasLength(14));
    expect(input.days.first.date, _today.addDays(-13));
    expect(input.days.last.date, _today);
    expect(input.days.last.weekday, AiWeekday.tue);
    expect([for (final d in input.days) d.steps].nonNulls, hasLength(2));
  });

  test('five days with data is the threshold', () {
    final four = buildAiPayloadResult(_assemble(_sources(stepDays: 4)));
    final five = buildAiPayloadResult(_assemble(_sources(stepDays: 5)));

    expect(four, isA<AiPayloadNotEnoughData>());
    expect((four as AiPayloadNotEnoughData).days, 4);
    expect(five, isA<AiPayloadReady>());
  });

  test('food reaches the payload only when the reader supplied it', () {
    final without = buildAiPayloadResult(_assemble(_sources(stepDays: 7)));
    final withFood = buildAiPayloadResult(
      _assemble(
        _sources(
          stepDays: 7,
          food: const AiFoodSummary(completeDays: 4, plateScore: 6.5),
        ),
      ),
    );

    Map<String, Object?> map(AiPayloadResult r) =>
        (r as AiPayloadReady).payload.contextMap;
    expect(map(without).containsKey('food'), isFalse);
    expect(map(withFood)['food'], {'complete_days': 4, 'plate_score': 6.5});
  });

  test('a night across a DST change keeps its local bedtime and wake', () {
    const dstDay = LocalDate(2026, 10, 25);
    final night = SleepNight([
      SleepSpan(
        start: DateTime.utc(2026, 10, 24, 21, 30),
        end: DateTime.utc(2026, 10, 25),
        phase: SleepPhase.light,
        utcOffset: const Duration(hours: 2),
      ),
      SleepSpan(
        start: DateTime.utc(2026, 10, 25, 1),
        end: DateTime.utc(2026, 10, 25, 6),
        phase: SleepPhase.deep,
        utcOffset: const Duration(hours: 1),
      ),
    ]);
    final input = _assemble(
      AiContextSources(
        today: dstDay,
        replyLanguage: 'en',
        units: const AiUnits(),
        profile: const AiProfileInput(),
        hasRing: true,
        importedIncluded: false,
        nights: {dstDay: night},
      ),
    );

    final row = input.days.last;
    expect(row.bedtime?.format(round15: false), '23:30');
    expect(row.wake?.format(round15: false), '07:00');
  });

  test('facts use the fixed metric labels and safe ids', () {
    final input = _assemble(_sources(stepDays: 7));

    expect(input.facts.map((f) => f.id), ['f.steps.last', 'f.steps.avg']);
    expect(input.facts.first.label, AiDailyMetric.steps.latestLabel);
    expect(input.facts.first.value, 5000);
    expect(input.facts.first.days, 7);
  });
}
