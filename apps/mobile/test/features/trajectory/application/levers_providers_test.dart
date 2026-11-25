import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/domain/heart_history_reader.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/domain/imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/domain/sleep_history_reader.dart';
import 'package:open_ring/features/trajectory/application/levers_providers.dart';
import 'package:open_ring/features/trajectory/domain/levers_view.dart';
import 'package:open_ring/features/trends/application/trends_providers.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

const _today = LocalDate(2026, 11, 25);
const _yesterday = LocalDate(2026, 11, 24);
const Set<ModuleId> _bodyAndTrajectory = {ModuleId.body, ModuleId.trajectory};
final _instant = DateTime.utc(2026, 11, 25, 12);
const _hour = Duration(hours: 1);

final class _FakeActivity implements ActivityHistoryReader {
  new(this.slots, {this.failure});

  final List<ActivitySlot> slots;
  final Error? failure;
  final List<({LocalDate from, LocalDate to})> calls = [];

  @override
  Future<List<DailyActivity>> dailyActivity({
    required LocalDate from,
    required LocalDate to,
  }) async => const [];

  @override
  Future<List<ActivitySlot>> activitySlots({
    required LocalDate from,
    required LocalDate to,
  }) async {
    calls.add((from: from, to: to));
    final error = failure;
    if (error != null) throw error;
    return [
      for (final slot in slots)
        if (slot.date.compareTo(from) >= 0 && slot.date.compareTo(to) <= 0)
          slot,
    ];
  }
}

final class _FakeSleep implements SleepHistoryReader {
  new(this.spans, {this.failure});

  final List<SleepSpan> spans;
  final Error? failure;
  int calls = 0;

  @override
  Future<List<SleepSpan>> sleepSpans({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return [
      for (final span in spans)
        if (span.start.isBefore(to) && span.end.isAfter(from)) span,
    ];
  }
}

final class _FakeImported implements ImportedSleepReader {
  new(this.imported);

  final ImportedSleep imported;
  int calls = 0;

  @override
  Future<ImportedSleep> importedSleep({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    return imported;
  }
}

final class _FakeHeart implements HeartHistoryReader {
  new(this.samples, {this.failure});

  final List<BpmSample> samples;
  final Error? failure;
  int calls = 0;

  @override
  Future<List<BpmSample>> heartRate({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return [
      for (final sample in samples)
        if (!sample.at.isBefore(from) && sample.at.isBefore(to)) sample,
    ];
  }

  @override
  Future<List<HrvReading>> hrv({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<List<Spo2Reading>> spo2({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<List<StressReading>> stress({
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

ActivitySlot _slot(
  DateTime start, {
  int steps = 0,
  Duration offset = Duration.zero,
}) => ActivitySlot(
  start: start,
  utcOffset: offset,
  duration: _hour,
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

// Hourly buckets from [firstHour] on the wall clock of [offset].
List<ActivitySlot> _day(
  LocalDate date, {
  int hours = 10,
  int firstHour = 8,
  int stepsEach = 0,
  Duration offset = Duration.zero,
}) => [
  for (var i = 0; i < hours; i++)
    _slot(
      DateTime.utc(
        date.year,
        date.month,
        date.day,
        firstHour + i,
      ).subtract(offset),
      steps: stepsEach,
      offset: offset,
    ),
];

List<LocalDate> _daysEnding(LocalDate last, int count) => [
  for (var i = count - 1; i >= 0; i--) last.addDays(-i),
];

List<ActivitySlot> _validDays(
  LocalDate last,
  int count, {
  int stepsEach = 100,
}) => [
  for (final date in _daysEnding(last, count))
    ..._day(date, stepsEach: stepsEach),
];

List<SleepSpan> _nights(int count) => [
  for (var i = -1; i < count; i++)
    () {
      final date = _yesterday.addDays(-count + 1 + i);
      final start = DateTime.utc(date.year, date.month, date.day, 23);
      return SleepSpan(
        start: start,
        end: start.add(const Duration(hours: 8)),
        phase: SleepPhase.light,
        utcOffset: Duration.zero,
      );
    }(),
];

List<BpmSample> _worn(Iterable<LocalDate> days) => [
  for (final date in days)
    (at: DateTime.utc(date.year, date.month, date.day, 12), bpm: 60),
];

TrendHistory _history({
  List<DailyValue> resting = const [],
  List<DailyValue> duration = const [],
}) => TrendHistory(
  today: _today,
  values: {
    TrendMetric.restingHeartRate: resting,
    TrendMetric.sleepDuration: duration,
  },
  bands: const {},
);

List<DailyValue> _series(int count, {double start = 50, double perDay = 0}) => [
  for (var i = 0; i < count; i++)
    (date: _today.addDays(i - count + 1), value: start + perDay * i),
];

final class _Rig {
  new({
    Set<ModuleId> modules = _bodyAndTrajectory,
    List<ActivitySlot> slots = const [],
    Error? activityFailure,
    List<SleepSpan> sleep = const [],
    Error? sleepFailure,
    ImportedSleep imported = noImportedSleep,
    List<BpmSample> heart = const [],
    Error? heartFailure,
    TrendHistory? history,
    Error? historyFailure,
  }) : activity = _FakeActivity(slots, failure: activityFailure),
       sleepReader = _FakeSleep(sleep, failure: sleepFailure),
       importedReader = _FakeImported(imported),
       heartReader = _FakeHeart(heart, failure: heartFailure) {
    container = ProviderContainer.test(
      overrides: [
        moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
        clockProvider.overrideWithValue(() => _instant),
        currentDateProvider.overrideWithValue(_today),
        activityHistoryReaderProvider.overrideWithValue(activity),
        sleepHistoryReaderProvider.overrideWithValue(sleepReader),
        importedSleepReaderProvider.overrideWithValue(importedReader),
        heartHistoryReaderProvider.overrideWithValue(heartReader),
        trendHistoryProvider.overrideWith((ref) async {
          historyReads++;
          final error = historyFailure;
          if (error != null) throw error;
          return history ?? _history();
        }),
      ],
    );
  }

  final _FakeActivity activity;
  final _FakeSleep sleepReader;
  final _FakeImported importedReader;
  final _FakeHeart heartReader;
  late final ProviderContainer container;
  int historyReads = 0;

  int get readerCalls =>
      activity.calls.length +
      sleepReader.calls +
      importedReader.calls +
      heartReader.calls +
      historyReads;

  Future<LeversView> view() => container.read(leversProvider.future);

  Future<Map<RingLever, LeverReading>> levers() async {
    final result = await view();
    expect(result, isA<LeversReady>());
    return (result as LeversReady).levers;
  }
}

void main() {
  late void Function(String?, {int? wrapWidth}) originalDebugPrint;
  late List<String> logged;

  setUp(() {
    originalDebugPrint = debugPrint;
    logged = [];
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
  });

  tearDown(() => debugPrint = originalDebugPrint);

  group('leversProvider', () {
    test('1. Trajectory off gives Off and no reader is called', () async {
      final rig = _Rig(modules: const {ModuleId.body});

      expect(await rig.view(), isA<LeversOff>());
      expect(rig.readerCalls, 0);
    });

    test('1. Body off gives Off and no reader is called', () async {
      final rig = _Rig(modules: const {ModuleId.trajectory});

      expect(await rig.view(), isA<LeversOff>());
      expect(rig.readerCalls, 0);
    });

    test('2. 10 h of buckets with 0 steps is a valid day of value 0', () async {
      final rig = _Rig(slots: _validDays(_yesterday, 54, stepsEach: 0));

      final steps = (await rig.levers())[RingLever.steps]!;

      expect(steps.validDays, 54);
      expect(steps.trend, isNotNull);
      expect(steps.trend!.typical, 0);
    });

    test(
      '2. the value of a valid day is the sum of its bucket steps',
      () async {
        final rig = _Rig(slots: _validDays(_yesterday, 54));

        final steps = (await rig.levers())[RingLever.steps]!;

        expect(steps.trend!.typical, 1000);
      },
    );

    test('2. a day with 9 h of buckets is excluded', () async {
      final slots = [
        ..._validDays(_yesterday.addDays(-1), 53),
        ..._day(_yesterday, hours: 9),
      ];
      final rig = _Rig(slots: slots);

      final steps = (await rig.levers())[RingLever.steps]!;

      expect(steps.validDays, 53);
      expect(steps.trend, isNull);
    });

    test('2. a nap inside the waking day is subtracted', () async {
      final napDay = _yesterday.addDays(-10);
      final nap = SleepSpan(
        start: DateTime.utc(napDay.year, napDay.month, napDay.day, 12),
        end: DateTime.utc(napDay.year, napDay.month, napDay.day, 14),
        phase: SleepPhase.light,
        utcOffset: Duration.zero,
      );
      final slots = [
        for (final date in _daysEnding(_yesterday, 54))
          ..._day(date, hours: 11, stepsEach: 100),
      ];
      final rig = _Rig(slots: slots, sleep: [nap]);

      final steps = (await rig.levers())[RingLever.steps]!;

      expect(steps.validDays, 53);
      expect(steps.trend, isNull);
    });

    test('2. a bucket is dated by its own offset, past UTC midnight', () async {
      const offset = Duration(hours: -3);
      final slots = _day(
        _yesterday,
        firstHour: 14,
        stepsEach: 100,
        offset: offset,
      );
      final rig = _Rig(slots: slots);

      final steps = (await rig.levers())[RingLever.steps]!;

      expect(steps.validDays, 1);
    });

    test('2. a time zone change inside the window keeps every day', () async {
      final dates = _daysEnding(_yesterday, 54);
      final slots = [
        for (final (index, date) in dates.indexed)
          ..._day(
            date,
            firstHour: 14,
            stepsEach: 100,
            offset: index < 27
                ? const Duration(hours: -3)
                : const Duration(hours: 9),
          ),
      ];
      final rig = _Rig(slots: slots);

      final steps = (await rig.levers())[RingLever.steps]!;

      expect(steps.validDays, 54);
      expect(steps.trend, isNotNull);
    });

    test('2. steps read a 90 day window that ends yesterday', () async {
      final rig = _Rig(slots: _validDays(_yesterday, 54));

      await rig.view();

      final calls = rig.activity.calls;
      expect(calls, isNotEmpty);
      expect(calls.every((call) => call.to.compareTo(_yesterday) <= 0), isTrue);
      expect(
        calls.any((call) => call.from.compareTo(_yesterday.addDays(-89)) <= 0),
        isTrue,
      );
    });

    test('2. a valid day today is not counted, it is partial', () async {
      final slots = [
        ..._validDays(_yesterday, 53),
        ..._day(_today, stepsEach: 100),
      ];
      final rig = _Rig(slots: slots);

      final steps = (await rig.levers())[RingLever.steps]!;

      expect(steps.validDays, 53);
    });

    test('5. 53 valid days give trend null with validDays 53', () async {
      final rig = _Rig(slots: _validDays(_yesterday, 53));

      final steps = (await rig.levers())[RingLever.steps]!;

      expect(steps.validDays, 53);
      expect(steps.trend, isNull);
    });

    test('5. 54 valid days give a trend', () async {
      final rig = _Rig(slots: _validDays(_yesterday, 54));

      final steps = (await rig.levers())[RingLever.steps]!;

      expect(steps.validDays, 54);
      expect(steps.trend, isNotNull);
      expect(steps.trend!.validDays, 54);
    });

    test('5. a lever with no data has 0 valid days and no trend', () async {
      final rig = _Rig();

      final levers = await rig.levers();

      expect(levers.keys, containsAll(RingLever.values));
      for (final lever in RingLever.values) {
        expect(levers[lever]!.validDays, 0);
        expect(levers[lever]!.trend, isNull);
      }
    });

    test('5. resting heart rate reads 90 days ending today', () async {
      final rig = _Rig(history: _history(resting: _series(90, perDay: 0.1)));

      final reading = (await rig.levers())[RingLever.restingHeartRate]!;

      expect(reading.validDays, 90);
      expect(reading.trend!.slopePerDay, closeTo(0.1, 1e-9));
    });

    test('5. sleep duration with 53 days has no trend', () async {
      final rig = _Rig(history: _history(duration: _series(53, start: 450)));

      final reading = (await rig.levers())[RingLever.sleepDuration]!;

      expect(reading.validDays, 53);
      expect(reading.trend, isNull);
    });

    test('5. sleep duration with 54 days has a trend', () async {
      final rig = _Rig(history: _history(duration: _series(54, start: 450)));

      final reading = (await rig.levers())[RingLever.sleepDuration]!;

      expect(reading.validDays, 54);
      expect(reading.trend!.typical, 450);
    });

    test(
      '3. regularity counts a pair for each worn day after the first',
      () async {
        final worn = _daysEnding(_yesterday, 60);
        final rig = _Rig(sleep: _nights(100), heart: _worn(worn));

        final reading = (await rig.levers())[RingLever.sleepRegularity]!;

        expect(reading.validDays, 59);
        expect(reading.trend!.typical, 100);
      },
    );

    test(
      '4. a worn day that is missing breaks both pairs it belongs to',
      () async {
        final worn = _daysEnding(_yesterday, 60)
          ..remove(_yesterday.addDays(-20));
        final rig = _Rig(sleep: _nights(100), heart: _worn(worn));

        final reading = (await rig.levers())[RingLever.sleepRegularity]!;

        expect(reading.validDays, 57);
      },
    );

    test('4. a night with no heart rate on its days is not regular', () async {
      final rig = _Rig(sleep: _nights(100));

      final reading = (await rig.levers())[RingLever.sleepRegularity]!;

      expect(reading.validDays, 0);
      expect(reading.trend, isNull);
    });

    test('4. imported sleep with no ring heart rate gives no value', () async {
      final imported = (
        priority: ['imported', ringSource],
        spans: {'imported': _nights(100)},
      );
      final rig = _Rig(imported: imported);

      final reading = (await rig.levers())[RingLever.sleepRegularity]!;

      expect(reading.validDays, 0);
      expect(reading.trend, isNull);
    });

    test(
      '3. regularity ignores a worn day today, the window ends yesterday',
      () async {
        final worn = [..._daysEnding(_yesterday, 53), _today];
        final rig = _Rig(sleep: _nights(100), heart: _worn(worn));

        final reading = (await rig.levers())[RingLever.sleepRegularity]!;

        expect(reading.validDays, 52);
      },
    );

    test('6. an activity reader that throws gives Error and logs it', () async {
      final failure = StateError('activity unreadable');
      final rig = _Rig(activityFailure: failure);

      final view = await rig.view();

      expect(view, isA<LeversError>());
      expect((view as LeversError).error, same(failure));
      expect(logged.join('\n'), contains('activity unreadable'));
    });

    test(
      '6. a heart reader that throws gives Error, not a partial view',
      () async {
        final rig = _Rig(
          slots: _validDays(_yesterday, 54),
          heartFailure: StateError('heart unreadable'),
        );

        final view = await rig.view();

        expect(view, isA<LeversError>());
        expect(logged.join('\n'), contains('heart unreadable'));
      },
    );

    test('6. a sleep reader that throws gives Error', () async {
      final rig = _Rig(
        slots: _validDays(_yesterday, 54),
        sleepFailure: StateError('sleep unreadable'),
      );

      expect(await rig.view(), isA<LeversError>());
    });

    test('6. a trend history that throws gives Error', () async {
      final rig = _Rig(historyFailure: StateError('history unreadable'));

      expect(await rig.view(), isA<LeversError>());
    });
  });
}
