import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

import 'trajectory_series.dart';

EnergyBalanceReady readyOf(EnergyBalance balance) {
  expect(balance, isA<EnergyBalanceReady>());
  return balance as EnergyBalanceReady;
}

LocalDate blockFrom(EnergyBalance balance) {
  expect(balance, isA<EnergyBalanceBlock>());
  return (balance as EnergyBalanceBlock).from;
}

int countOf(EnergyBalance balance) {
  expect(balance, isA<EnergyBalanceCount>());
  return (balance as EnergyBalanceCount).weighIns;
}

EnergyBalance balanceAt(double slope, int day, {LocalDate? blockStart}) {
  final series = prototypeSeries(slope, upto: day);
  final today = seriesStart.addDays(day);
  return energyBalance(
    weighIns: series,
    rate: weightRate(series, today: today),
    today: today,
    goalBlockStart: blockStart,
  );
}

EnergyBalance protoBalance(
  List<DailyValue> weighIns, {
  LocalDate? blockStart,
}) => energyBalance(
  weighIns: weighIns,
  rate: protoRate,
  today: seriesToday,
  goalBlockStart: blockStart,
);

const _building = WeightRateBuilding(daysMissing: 3, spanMissing: 2);

void main() {
  group('1. a stable series is Ready, balanced and shown as -100 to 100', () {
    EnergyBalanceReady stable() => readyOf(balanceAt(0, 24));

    test('low, mid and high are -108.07, -14.44 and 79.19 kcal a day', () {
      expect(stable().low, closeTo(-108.07, 0.01));
      expect(stable().mid, closeTo(-14.44, 0.01));
      expect(stable().high, closeTo(79.19, 0.01));
    });

    test('it counts the 25 weigh-ins of the window', () {
      expect(stable().weighIns, 25);
    });

    test('shown rounds each end to 50', () {
      expect(stable().shown, (low: -100, high: 100));
    });

    test('a range that spans zero is balanced', () {
      expect(stable().balanced, isTrue);
    });
  });

  group('1b. the kcal a day is perWeek over 7 times 7700', () {
    test('the prototype rate gives -477.96, -382.91 and -287.85', () {
      final balance = readyOf(protoBalance(straight(seriesToday, 20)));
      expect(balance.low, closeTo(-477.961, 0.001));
      expect(balance.mid, closeTo(-382.907, 0.001));
      expect(balance.high, closeTo(-287.852, 0.001));
      expect(balance.shown, (low: -500, high: -300));
      expect(balance.balanced, isFalse);
    });
  });

  group('balanced is low <= 0 && high >= 0', () {
    EnergyBalanceReady at(double low, double high) =>
        EnergyBalanceReady(low: low, mid: 0, high: high, weighIns: 20);

    test('a range with low above zero is not balanced', () {
      expect(at(0.1, 100).balanced, isFalse);
    });

    test('a range with high below zero is not balanced', () {
      expect(at(-100, -0.1).balanced, isFalse);
    });

    test('low exactly zero and high exactly zero are balanced', () {
      expect(at(0, 100).balanced, isTrue);
      expect(at(-100, 0).balanced, isTrue);
    });
  });

  group('2. the goal block holds the balance for 41 days', () {
    const start = LocalDate(2026, 11, 16);

    test('day 24 of the block is Block, resuming on 2026-12-27', () {
      expect(
        blockFrom(balanceAt(0.05, 24, blockStart: start)),
        const LocalDate(2026, 12, 27),
      );
    });

    test('day 40 is still Block', () {
      expect(
        blockFrom(balanceAt(0.05, 40, blockStart: start)),
        const LocalDate(2026, 12, 27),
      );
    });

    test('day 41 is Ready, -428.94 to -248.64, shown -450 to -250', () {
      final balance = readyOf(balanceAt(0.05, 41, blockStart: start));
      expect(balance.low, closeTo(-428.94, 0.01));
      expect(balance.high, closeTo(-248.64, 0.01));
      expect(balance.weighIns, 27);
      expect(balance.shown, (low: -450, high: -250));
      expect(balance.balanced, isFalse);
    });

    test('a block that starts today is Block, from today plus 41', () {
      final balance = balanceAt(0, 24, blockStart: seriesToday);
      expect(blockFrom(balance), const LocalDate(2027, 1, 20));
    });

    test('a block start after today is not Block', () {
      final balance = balanceAt(0, 24, blockStart: seriesToday.addDays(1));
      expect(balance, isA<EnergyBalanceReady>());
    });

    test('a block start far in the future is not Block', () {
      final balance = balanceAt(0, 24, blockStart: const LocalDate(2027, 6, 1));
      expect(balance, isA<EnergyBalanceReady>());
    });

    test('no block start is Ready', () {
      expect(balanceAt(0.05, 24), isA<EnergyBalanceReady>());
    });
  });

  group('3. too few weigh-ins and a building rate', () {
    test('19 weigh-ins in the window is Count with 19', () {
      expect(countOf(protoBalance(straight(seriesToday, 19))), 19);
    });

    test('20 weigh-ins in the window is Ready', () {
      final balance = readyOf(protoBalance(straight(seriesToday, 20)));
      expect(balance.weighIns, 20);
    });

    test('weigh-ins older than the 28 day window do not count', () {
      final old = [
        for (var i = 28; i < 40; i++)
          (date: seriesToday.addDays(-i), value: 78.0),
      ];
      final balance = protoBalance([...straight(seriesToday, 19), ...old]);
      expect(countOf(balance), 19);
    });

    test('two weigh-ins on one day count as one', () {
      final doubled = [
        ...straight(seriesToday, 19),
        (date: seriesToday, value: 79.0),
      ];
      expect(countOf(protoBalance(doubled)), 19);
    });

    test('a building rate is NoRate', () {
      final balance = energyBalance(
        weighIns: straight(seriesToday, 25),
        rate: _building,
        today: seriesToday,
      );
      expect(balance, isA<EnergyBalanceNoRate>());
    });

    test('the rate is checked before the count', () {
      final balance = energyBalance(
        weighIns: straight(seriesToday, 3),
        rate: _building,
        today: seriesToday,
      );
      expect(balance, isA<EnergyBalanceNoRate>());
    });

    test('the count is checked before the block', () {
      final balance = protoBalance(
        straight(seriesToday, 19),
        blockStart: seriesToday,
      );
      expect(balance, isA<EnergyBalanceCount>());
    });

    test('the rate is checked before the block', () {
      final balance = energyBalance(
        weighIns: straight(seriesToday, 25),
        rate: _building,
        today: seriesToday,
        goalBlockStart: seriesToday,
      );
      expect(balance, isA<EnergyBalanceNoRate>());
    });
  });
}
