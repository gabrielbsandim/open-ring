import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/domain/heart_history_reader.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/domain/imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/domain/sleep_history_reader.dart';

const _minusThreeHours = Duration(minutes: -180);
const _plusTenHours = Duration(hours: 10);
const _sunday = LocalDate(2026, 12, 13);
final _sundayNoon = DateTime.utc(2026, 12, 13, 12);

DateTime _instant(
  LocalDate date,
  int hour,
  int minute, [
  Duration offset = Duration.zero,
]) => DateTime.utc(
  date.year,
  date.month,
  date.day,
  hour,
  minute,
).subtract(offset);

SleepNight _nightOn(
  LocalDate day, {
  int bedHour = 23,
  int bedMinute = 0,
  int latencyMinutes = 0,
  int wakeHour = 7,
  int wakeMinute = 0,
  Duration offset = Duration.zero,
}) {
  final bedDate = bedHour < foodDayStartHour ? day.addDays(1) : day;
  final start = _instant(bedDate, bedHour, bedMinute, offset);
  final onset = start.add(Duration(minutes: latencyMinutes));
  final end = _instant(day.addDays(1), wakeHour, wakeMinute, offset);
  return SleepNight([
    if (latencyMinutes > 0)
      SleepSpan(
        start: start,
        end: onset,
        phase: SleepPhase.awake,
        utcOffset: offset,
      ),
    SleepSpan(
      start: onset,
      end: end,
      phase: SleepPhase.light,
      utcOffset: offset,
    ),
  ]);
}

Meal _mealAt(
  int id,
  LocalDate date,
  int hour,
  int minute, {
  int offsetMinutes = 0,
  MealKind? kind = MealKind.main,
  MealTags tags = const MealTags(protein: true),
  bool last = false,
}) {
  final at = _instant(date, hour, minute, Duration(minutes: offsetMinutes));
  return Meal(
    id: id,
    at: at,
    offsetMinutes: offsetMinutes,
    createdAt: at,
    kind: kind,
    tags: tags,
    last: last,
  );
}

List<BpmSample> _steadyBpm(SleepNight night, int bpm) => [
  (at: night.start, bpm: bpm),
  (at: night.start.add(const Duration(minutes: 10)), bpm: bpm),
  (at: night.start.add(const Duration(minutes: 20)), bpm: bpm),
];

List<HrvReading> _steadyHrv(SleepNight night, int milliseconds) => [
  (at: night.start, milliseconds: milliseconds),
  (
    at: night.start.add(const Duration(minutes: 30)),
    milliseconds: milliseconds,
  ),
  (
    at: night.start.add(const Duration(minutes: 60)),
    milliseconds: milliseconds,
  ),
];

final class _MutableSleepReader implements SleepHistoryReader {
  new([List<SleepSpan> initial = const []]) : spans = [...initial];

  final List<SleepSpan> spans;
  int calls = 0;

  @override
  Future<List<SleepSpan>> sleepSpans({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    return [
      for (final s in spans)
        if (s.end.isAfter(from) && s.start.isBefore(to)) s,
    ];
  }
}

final class _SpyImportedSleepReader implements ImportedSleepReader {
  new({this.spans = const {}, this.priority = const [ringSource]});

  final Map<String, List<SleepSpan>> spans;
  final List<String> priority;
  int calls = 0;

  @override
  Future<ImportedSleep> importedSleep({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    return (
      priority: priority,
      spans: {
        for (final MapEntry(:key, :value) in spans.entries)
          key: [
            for (final s in value)
              if (s.end.isAfter(from) && s.start.isBefore(to)) s,
          ],
      },
    );
  }
}

final class _SpyHeartReader implements HeartHistoryReader {
  new({this.heartRateSamples = const [], this.hrvReadings = const []});

  final List<BpmSample> heartRateSamples;
  final List<HrvReading> hrvReadings;
  final List<({DateTime from, DateTime to})> heartRateRanges = [];
  final List<({DateTime from, DateTime to})> hrvRanges = [];

  @override
  Future<List<BpmSample>> heartRate({
    required DateTime from,
    required DateTime to,
  }) async {
    heartRateRanges.add((from: from, to: to));
    return [
      for (final s in heartRateSamples)
        if (!s.at.isBefore(from) && !s.at.isAfter(to)) s,
    ];
  }

  @override
  Future<List<HrvReading>> hrv({
    required DateTime from,
    required DateTime to,
  }) async {
    hrvRanges.add((from: from, to: to));
    return [
      for (final r in hrvReadings)
        if (!r.at.isBefore(from) && !r.at.isAfter(to)) r,
    ];
  }

  @override
  Future<List<Spo2Reading>> spo2({
    required DateTime from,
    required DateTime to,
  }) => throw StateError('food nights never read SpO2');

  @override
  Future<List<StressReading>> stress({
    required DateTime from,
    required DateTime to,
  }) => throw StateError('food nights never read stress');
}

final class _ThrowingSleepReader implements SleepHistoryReader {
  const new();

  @override
  Future<List<SleepSpan>> sleepSpans({
    required DateTime from,
    required DateTime to,
  }) => throw StateError('sleepHistoryReaderProvider must not be called');
}

final class _ThrowingImportedSleepReader implements ImportedSleepReader {
  const new();

  @override
  Future<ImportedSleep> importedSleep({
    required DateTime from,
    required DateTime to,
  }) => throw StateError('importedSleepReaderProvider must not be called');
}

final class _ThrowingHeartReader implements HeartHistoryReader {
  const new();

  @override
  Future<List<BpmSample>> heartRate({
    required DateTime from,
    required DateTime to,
  }) => throw StateError('heartHistoryReaderProvider must not be called');

  @override
  Future<List<HrvReading>> hrv({
    required DateTime from,
    required DateTime to,
  }) => throw StateError('heartHistoryReaderProvider must not be called');

  @override
  Future<List<Spo2Reading>> spo2({
    required DateTime from,
    required DateTime to,
  }) => throw StateError('heartHistoryReaderProvider must not be called');

  @override
  Future<List<StressReading>> stress({
    required DateTime from,
    required DateTime to,
  }) => throw StateError('heartHistoryReaderProvider must not be called');
}

final class _ThrowingDayTagStore implements DayTagStore {
  const new();

  @override
  Future<Map<LocalDate, DayTag>> all() =>
      throw StateError('dayTagStoreProvider must not be called');

  @override
  Future<bool> put(LocalDate date, DayTag tag, {required DateTime now}) =>
      throw StateError('dayTagStoreProvider must not be called');

  @override
  Future<bool> remove(LocalDate date) =>
      throw StateError('dayTagStoreProvider must not be called');

  @override
  Future<int> count() =>
      throw StateError('dayTagStoreProvider must not be called');

  @override
  Future<int> clear() =>
      throw StateError('dayTagStoreProvider must not be called');
}

Future<ProviderContainer> _container({
  DateTime? now,
  Set<ModuleId> modules = const {ModuleId.food},
  SleepHistoryReader? sleep,
  ImportedSleepReader? imported,
  HeartHistoryReader? heart,
  DayTagStore? tags,
  List<Override> extra = const [],
}) async {
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => now ?? _sundayNoon),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      if (sleep != null) sleepHistoryReaderProvider.overrideWithValue(sleep),
      if (imported != null)
        importedSleepReaderProvider.overrideWithValue(imported),
      if (heart != null) heartHistoryReaderProvider.overrideWithValue(heart),
      if (tags != null) dayTagStoreProvider.overrideWithValue(tags),
      ...extra,
    ],
  );
  await container.read(enabledModulesProvider.future);
  return container;
}

void main() {
  group('criterion 1: foodNightOf and sleepOnsetWallClock', () {
    test('awake 23:00 to 23:15 then light sleep until 06:45 on wake date '
        '2026-12-01 at offset -180 closes 2026-11-30 with onset 23:15 UTC '
        'wall clock, samples in [start, end) and 180 min gap from 20:15 '
        'meal', () {
      const day = LocalDate(2026, 11, 30);
      final night = _nightOn(
        day,
        latencyMinutes: 15,
        wakeHour: 6,
        wakeMinute: 45,
        offset: _minusThreeHours,
      );
      final heartRate = <BpmSample>[
        (at: night.start.subtract(const Duration(minutes: 5)), bpm: 30),
        (at: night.start, bpm: 54),
        (at: night.start.add(const Duration(minutes: 10)), bpm: 56),
        (at: night.start.add(const Duration(minutes: 15)), bpm: 0),
        (at: night.start.add(const Duration(minutes: 20)), bpm: 58),
        (at: night.end.subtract(const Duration(minutes: 20)), bpm: 60),
        (at: night.end.subtract(const Duration(minutes: 10)), bpm: 60),
        (at: night.end, bpm: 30),
      ];
      final hrv = <HrvReading>[
        (
          at: night.start.subtract(const Duration(minutes: 1)),
          milliseconds: 99,
        ),
        (at: night.start, milliseconds: 42),
        (at: night.start.add(const Duration(minutes: 30)), milliseconds: 0),
        (at: night.start.add(const Duration(hours: 1)), milliseconds: 45),
        (at: night.start.add(const Duration(hours: 2)), milliseconds: 48),
        (at: night.end, milliseconds: 120),
      ];
      final dinner = _mealAt(1, day, 20, 15, offsetMinutes: -180, last: true);

      final onset = sleepOnsetWallClock(night);
      final foodNight = foodNightOf(night, heartRate: heartRate, hrv: hrv);

      expect(night.date, const LocalDate(2026, 12, 1));
      expect(onset, DateTime.utc(2026, 11, 30, 23, 15));
      expect(onset!.isUtc, isTrue);
      expect(foodNight.day, day);
      expect(foodNight.sleepOnset, DateTime.utc(2026, 11, 30, 23, 15));
      expect(foodNight.sleepOnset!.isUtc, isTrue);
      expect(foodNight.heartRate, 56.0);
      expect(foodNight.hrv, 45.0);
      expect(
        lastMealToSleep([dinner.entry], foodNight.sleepOnset!),
        const Duration(minutes: 180),
      );
    });

    test('onset after midnight on Saturday morning closes Friday', () {
      const friday = LocalDate(2026, 12, 4);
      final night = _nightOn(
        friday,
        bedHour: 0,
        bedMinute: 20,
        wakeMinute: 30,
        offset: _minusThreeHours,
      );
      final dinner = _mealAt(1, friday, 20, 0, offsetMinutes: -180, last: true);

      final foodNight = foodNightOf(night);

      expect(night.date, const LocalDate(2026, 12, 5));
      expect(foodNight.day, friday);
      expect(foodNight.sleepOnset, DateTime.utc(2026, 12, 5, 0, 20));
      expect(
        lastMealToSleep([dinner.entry], foodNight.sleepOnset!),
        const Duration(minutes: 260),
      );
    });

    test('a night with only awake spans has null sleepOnset', () {
      final night = SleepNight([
        SleepSpan(
          start: DateTime.utc(2026, 11, 30, 23),
          end: DateTime.utc(2026, 12, 1, 6),
          phase: SleepPhase.awake,
          utcOffset: Duration.zero,
        ),
      ]);

      expect(sleepOnsetWallClock(night), isNull);
      expect(foodNightOf(night).sleepOnset, isNull);
      expect(foodNightOf(night).day, const LocalDate(2026, 11, 30));
    });
  });

  group('criterion 2: window on Sunday 2026-12-13 and sleepOnsetsOf', () {
    test('foodCompareLastNight is 2026-12-06 and foodFirstNight is '
        '2026-09-08 (96 days before Sunday today)', () {
      expect(foodCompareLastNight(_sunday), const LocalDate(2026, 12, 6));
      expect(foodFirstNight(_sunday), const LocalDate(2026, 9, 8));
      expect(_sunday.daysSince(foodFirstNight(_sunday)), 96);
    });

    test('collectFoodNights keeps [2026-09-08 .. 2026-12-12], drops '
        '2026-09-07 and 2026-12-13, sorts oldest day first, and '
        'sleepOnsetsOf maps nights with an onset', () {
      final tooOld = _nightOn(const LocalDate(2026, 9, 7));
      final firstKept = _nightOn(
        const LocalDate(2026, 9, 8),
        bedHour: 22,
        bedMinute: 45,
      );
      final middleAwakeOnly = SleepNight([
        SleepSpan(
          start: DateTime.utc(2026, 10, 10, 23),
          end: DateTime.utc(2026, 10, 11, 6, 30),
          phase: SleepPhase.awake,
          utcOffset: Duration.zero,
        ),
      ]);
      final lastKept = _nightOn(const LocalDate(2026, 12, 12), bedMinute: 30);
      final tonight = _nightOn(_sunday);

      final collected = collectFoodNights(
        today: _sunday,
        nights: [lastKept, tonight, middleAwakeOnly, tooOld, firstKept],
        heartRate: [..._steadyBpm(firstKept, 52), ..._steadyBpm(lastKept, 58)],
        hrv: [..._steadyHrv(firstKept, 48), ..._steadyHrv(lastKept, 40)],
      );

      expect(
        [for (final n in collected) n.day],
        [
          const LocalDate(2026, 9, 8),
          const LocalDate(2026, 10, 10),
          const LocalDate(2026, 12, 12),
        ],
      );
      expect(collected.first.heartRate, 52.0);
      expect(collected.first.hrv, 48.0);
      expect(collected[1].sleepOnset, isNull);
      expect(collected.last.heartRate, 58.0);
      expect(collected.last.hrv, 40.0);
      expect(sleepOnsetsOf(collected), {
        const LocalDate(2026, 9, 8): DateTime.utc(2026, 9, 8, 22, 45),
        const LocalDate(2026, 12, 12): DateTime.utc(2026, 12, 12, 23, 30),
      });
    });

    test('collectFoodNights drops excluded food days', () {
      const keptDay = LocalDate(2026, 12, 5);
      const excludedDay = LocalDate(2026, 12, 6);

      final collected = collectFoodNights(
        today: _sunday,
        nights: [_nightOn(keptDay), _nightOn(excludedDay)],
        excluded: const {excludedDay},
      );

      expect([for (final n in collected) n.day], [keptDay]);
    });
  });

  group('criterion 3: day tags and the Open Score gate', () {
    const sickDay = LocalDate(2026, 12, 3);
    const travelDay = LocalDate(2026, 12, 4);
    const restDay = LocalDate(2026, 12, 5);
    const plainDay = LocalDate(2026, 12, 6);

    List<SleepSpan> fourNights() => [
      ..._nightOn(sickDay).spans,
      ..._nightOn(travelDay).spans,
      ..._nightOn(restDay).spans,
      ..._nightOn(plainDay).spans,
    ];

    test('with Open Score on, sick and travel drop their FoodNight.day while '
        'rest stays', () async {
      final container = await _container(
        modules: const {ModuleId.food, ModuleId.openScore},
        sleep: _MutableSleepReader(fourNights()),
        tags: InMemoryDayTagStore(const {
          sickDay: DayTag.sick,
          travelDay: DayTag.travel,
          restDay: DayTag.rest,
        }),
      );

      final nights = await container.read(foodNightsProvider.future);

      expect([for (final n in nights) n.day], [restDay, plainDay]);
    });

    test('with Open Score off, tagged days stay and a throwing '
        'dayTagStoreProvider is never read', () async {
      final container = await _container(
        sleep: _MutableSleepReader(fourNights()),
        tags: const _ThrowingDayTagStore(),
      );

      final nights = await container.read(foodNightsProvider.future);

      expect(
        [for (final n in nights) n.day],
        [sickDay, travelDay, restDay, plainDay],
      );
    });
  });

  group('criterion 4: Food gate, empty nights and dataRevision', () {
    test('with Food off, foodNightsProvider returns [] without touching '
        'sleep, imported sleep, heart or day tag readers', () async {
      final container = await _container(
        modules: const {ModuleId.openScore},
        sleep: const _ThrowingSleepReader(),
        imported: const _ThrowingImportedSleepReader(),
        heart: const _ThrowingHeartReader(),
        tags: const _ThrowingDayTagStore(),
      );

      final nights = await container.read(foodNightsProvider.future);

      expect(nights, isEmpty);
    });

    test('with Food on and no kept nights, heartHistoryReaderProvider is '
        'never called', () async {
      final outOfWindow = _MutableSleepReader([
        ..._nightOn(const LocalDate(2026, 9, 7)).spans,
        ..._nightOn(_sunday).spans,
      ]);
      final container = await _container(
        sleep: outOfWindow,
        heart: const _ThrowingHeartReader(),
      );

      final nights = await container.read(foodNightsProvider.future);

      expect(nights, isEmpty);
      expect(outOfWindow.calls, 1);
    });

    test('queries heartRate and hrv once over [min(start), max(end)] of kept '
        'nights and keeps a night recorded under another UTC offset', () async {
      final oldestAtPlusTen = _nightOn(
        const LocalDate(2026, 9, 8),
        bedHour: 22,
        bedMinute: 10,
        wakeHour: 6,
        wakeMinute: 20,
        offset: _plusTenHours,
      );
      final latestAtMinusThree = _nightOn(
        const LocalDate(2026, 12, 12),
        bedMinute: 40,
        wakeMinute: 10,
        offset: _minusThreeHours,
      );
      final heart = _SpyHeartReader(
        heartRateSamples: [
          ..._steadyBpm(oldestAtPlusTen, 51),
          ..._steadyBpm(latestAtMinusThree, 59),
        ],
        hrvReadings: [
          ..._steadyHrv(oldestAtPlusTen, 52),
          ..._steadyHrv(latestAtMinusThree, 41),
        ],
      );
      final imported = _SpyImportedSleepReader(
        priority: const [ringSource, 'com.example.health'],
        spans: {'com.example.health': latestAtMinusThree.spans},
      );
      final container = await _container(
        sleep: _MutableSleepReader(oldestAtPlusTen.spans),
        imported: imported,
        heart: heart,
      );

      final nights = await container.read(foodNightsProvider.future);

      expect(imported.calls, 1);
      expect(heart.heartRateRanges, [
        (from: oldestAtPlusTen.start, to: latestAtMinusThree.end),
      ]);
      expect(heart.hrvRanges, [
        (from: oldestAtPlusTen.start, to: latestAtMinusThree.end),
      ]);
      expect(
        [for (final n in nights) n.day],
        [const LocalDate(2026, 9, 8), const LocalDate(2026, 12, 12)],
      );
      expect(nights.first.sleepOnset, DateTime.utc(2026, 9, 8, 22, 10));
      expect(nights.first.heartRate, 51.0);
      expect(nights.first.hrv, 52.0);
      expect(nights.last.sleepOnset, DateTime.utc(2026, 12, 12, 23, 40));
      expect(nights.last.heartRate, 59.0);
      expect(nights.last.hrv, 41.0);
    });

    test('bumping dataRevisionProvider re-reads the nights', () async {
      final sleep = _MutableSleepReader();
      final container = await _container(sleep: sleep);
      expect(await container.read(foodNightsProvider.future), isEmpty);

      sleep.spans.addAll(_nightOn(const LocalDate(2026, 12, 10)).spans);
      container.read(dataRevisionProvider.notifier).bump();
      final nights = await container.read(foodNightsProvider.future);

      expect([for (final n in nights) n.day], [const LocalDate(2026, 12, 10)]);
    });
  });

  group('criterion 5: end-to-end with compareLink', () {
    test('synthetic SleepNights and Meals ending at foodCompareLastNight '
        'fed through foodNightsProvider into compareLink produce a '
        'LinkPattern', () async {
      final lastNight = foodCompareLastNight(_sunday);
      final spans = <SleepSpan>[];
      final heartRate = <BpmSample>[];
      final meals = <Meal>[];
      var mealId = 1;

      for (var pair = 0; pair < foodMinPairs; pair++) {
        final weekSunday = lastNight.addDays(-7 * (pair ~/ 2));
        final exposedDay = pair.isEven
            ? weekSunday.addDays(-6)
            : weekSunday.addDays(-3);
        final controlDay = pair.isEven ? weekSunday.addDays(-5) : weekSunday;
        final exposedNight = _nightOn(
          exposedDay,
          latencyMinutes: 30,
          offset: _minusThreeHours,
        );
        final controlNight = _nightOn(
          controlDay,
          bedMinute: 30,
          offset: _minusThreeHours,
        );
        spans
          ..addAll(exposedNight.spans)
          ..addAll(controlNight.spans);
        heartRate
          ..addAll(_steadyBpm(exposedNight, pair.isEven ? 60 : 62))
          ..addAll(_steadyBpm(controlNight, 55));
        meals
          ..add(_mealAt(mealId++, exposedDay, 8, 0, offsetMinutes: -180))
          ..add(
            _mealAt(
              mealId++,
              exposedDay,
              22,
              30,
              offsetMinutes: -180,
              last: true,
            ),
          )
          ..add(_mealAt(mealId++, controlDay, 8, 0, offsetMinutes: -180))
          ..add(
            _mealAt(
              mealId++,
              controlDay,
              19,
              0,
              offsetMinutes: -180,
              last: true,
            ),
          );
      }

      final container = await _container(
        sleep: _MutableSleepReader(spans),
        heart: _SpyHeartReader(heartRateSamples: heartRate),
      );
      final nights = await container.read(foodNightsProvider.future);
      final comparison = compareLink(
        link: FoodLink.lateLastMeal,
        outcome: NightOutcome.heartRate,
        lastNight: lastNight,
        nights: nights,
        meals: [for (final meal in meals) meal.entry],
      );

      expect(nights.last.day, lastNight);
      expect(
        comparison,
        isA<LinkPattern>()
            .having((r) => r.pairs, 'pairs', foodMinPairs)
            .having((r) => r.mean, 'mean', closeTo(6, 1e-9))
            .having((r) => r.low, 'low', greaterThan(0)),
      );
    });

    test('between 00:00 and 04:59 on Monday, keeps the oldest 7 nights of the '
        '05:00 food-day 90-night window', () async {
      final monday1Am = DateTime(2026, 6, 15, 1);
      final keptOldest = _nightOn(const LocalDate(2026, 3, 10));
      final tooOld = _nightOn(const LocalDate(2026, 3, 9));
      final container = await _container(
        now: monday1Am,
        sleep: _MutableSleepReader([...tooOld.spans, ...keptOldest.spans]),
      );

      final nights = await container.read(foodNightsProvider.future);
      expect([for (final n in nights) n.day], const [LocalDate(2026, 3, 10)]);
    });
  });
}
