import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';

const _saturday = LocalDate(2026, 12, 6);
const _sunday = LocalDate(2026, 12, 7);
const _monday = LocalDate(2026, 12, 8);

final _lateSaturday = DateTime(2026, 12, 6, 23, 50);
final _earlySunday = DateTime(2026, 12, 7, 0, 10);

final _watchesDate = Provider<LocalDate>(
  (ref) => ref.watch(currentDateProvider),
);

ProviderContainer _container(DateTime Function() clock) =>
    ProviderContainer(overrides: [clockProvider.overrideWithValue(clock)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('case 1: DayRoll.check', () {
    test('is false with no roll while the date holds, then true with one '
        'roll once it moved', () {
      var now = _lateSaturday;
      var rolls = 0;
      final dayRoll = DayRoll(
        clock: () => now,
        current: () => _saturday,
        roll: () => rolls++,
      );

      final before = dayRoll.check();
      final rollsBefore = rolls;
      now = _earlySunday;
      final after = dayRoll.check();

      expect(before, isFalse);
      expect(rollsBefore, 0);
      expect(after, isTrue);
      expect(rolls, 1);
    });
  });

  group('case 2: dayRollProvider rolls currentDateProvider', () {
    test('after midnight check() gives the new date and notifies a '
        'dependent once', () async {
      var now = _lateSaturday;
      final container = _container(() => now);
      addTearDown(container.dispose);
      var notified = 0;
      container.listen(_watchesDate, (_, _) => notified++);
      expect(container.read(currentDateProvider), _saturday);

      now = _earlySunday;
      container.read(dayRollProvider).check();
      await pumpEventQueue();

      expect(container.read(currentDateProvider), _sunday);
      expect(notified, 1);
    });

    test('check() on the same day notifies nobody', () async {
      var now = _lateSaturday;
      final container = _container(() => now);
      addTearDown(container.dispose);
      var notified = 0;
      container.listen(_watchesDate, (_, _) => notified++);

      now = DateTime(2026, 12, 6, 23, 59);
      final moved = container.read(dayRollProvider).check();
      await pumpEventQueue();

      expect(moved, isFalse);
      expect(container.read(currentDateProvider), _saturday);
      expect(notified, 0);
    });

    testWidgets('a resume checks the day', (tester) async {
      var now = _lateSaturday;
      final container = _container(() => now)
        ..read(currentDateProvider)
        ..read(dayRollProvider);

      now = _earlySunday;
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(container.read(currentDateProvider), _sunday);
      container.dispose();
    });

    testWidgets('the midnight timer rolls the date and rearms for the next '
        'one', (tester) async {
      var now = _lateSaturday;
      final seen = <LocalDate>[];
      final container = _container(() => now)
        ..listen(currentDateProvider, (_, next) => seen.add(next))
        ..read(dayRollProvider);

      now = _earlySunday;
      await tester.pump(const Duration(minutes: 11));
      expect(seen, [_sunday]);

      now = DateTime(2026, 12, 8, 0, 10);
      await tester.pump(const Duration(hours: 25));

      expect(seen, [_sunday, _monday]);
      container.dispose();
    });
  });

  group('case 3: DayRoll.untilNextDay', () {
    Duration until(DateTime now) => DayRoll(
      clock: () => now,
      current: () => LocalDate(now.year, now.month, now.day),
      roll: () {},
    ).untilNextDay();

    test('at 23:50 is 10 minutes', () {
      expect(until(_lateSaturday), const Duration(minutes: 10));
    });

    test('at 23:59:30 is 30 seconds', () {
      expect(
        until(DateTime(2026, 12, 6, 23, 59, 30)),
        const Duration(seconds: 30),
      );
    });

    test('just after midnight is the rest of the day', () {
      expect(
        until(DateTime(2026, 12, 7, 0, 10)),
        const Duration(hours: 23, minutes: 50),
      );
    });
  });

  group('review focus 1: the timer lives in dayRollProvider only', () {
    testWidgets('a reader of currentDateProvider leaves no timer pending', (
      tester,
    ) async {
      final container = _container(() => _lateSaturday);
      addTearDown(container.dispose);

      container
        ..read(currentDateProvider)
        ..read(_watchesDate);
    });

    testWidgets('disposing the container releases the midnight timer', (
      tester,
    ) async {
      _container(() => _lateSaturday)
        ..read(dayRollProvider)
        ..dispose();
    });
  });
}
