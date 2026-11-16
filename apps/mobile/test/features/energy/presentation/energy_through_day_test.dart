import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_parts.dart';
import 'package:open_ring/features/energy/presentation/energy_through_day.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

final _from = DateTime.utc(2026, 11, 10);
final _to = DateTime.utc(2026, 11, 11);

DateTime _at(int hour, [int minute = 0]) =>
    _from.add(Duration(hours: hour, minutes: minute));

EnergyCurve _curveAt(DateTime now) => energyCurve(
  sex: EnergySex.male,
  age: 30,
  kilograms: 70,
  centimeters: 175,
  slots: [
    (start: _at(8), duration: const Duration(hours: 1), steps: 4000),
    (start: _at(13), duration: const Duration(hours: 1), steps: 2500),
  ],
  workouts: [
    (
      start: _at(10, 15),
      end: _at(10, 55),
      elapsed: const Duration(minutes: 40),
      met: 6,
      storedKilocalories: 305,
    ),
  ],
  from: _from,
  to: _to,
  now: now,
);

final EnergyCurve _afternoon = _curveAt(_at(14, 30));

Future<void> _pump(
  WidgetTester tester, {
  EnergyCurve? curve,
  List<double>? usual,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(
    Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: EnergyThroughDay(
          curve: curve ?? _afternoon,
          utcOffset: Duration.zero,
          usual: usual,
        ),
      ),
    ),
  ),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: const [],
);

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(EnergyThroughDay));

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(_context(tester));

MetricFormat _format(WidgetTester tester) => MetricFormat.of(_context(tester));

String _text(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data!,
      final CaptionText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

String _rangeText(WidgetTester tester, EnergyRange range) {
  final format = _format(tester);
  return _l10n(tester).energyKcal(
    _l10n(tester)
        .energyRowRange(format.integer(range.low), format.integer(range.high)),
  );
}

Future<void> _tapHour(WidgetTester tester, double hour) async {
  final box = tester.getRect(find.byKey(EnergyThroughKeys.chart));
  const left = 40.0;
  const right = 8.0;
  final dx = left + (box.width - left - right) * hour / 24;
  await tester.tapAt(box.topLeft + Offset(dx, box.height / 2));
  await tester.pump();
}

void main() {
  group('the axis', () {
    test(
      'the top is the first thousand above the margin of the last point',
      () {
        final peak = _afternoon.points.last.day.total * (1 + energyDayMargin);

        expect(energyChartTop(_afternoon), (peak / 1000).ceil() * 1000);
        expect(energyChartTop(_curveAt(_at(0, 10))), 1000);
      },
    );

    test('the marks stay at four lines or fewer', () {
      expect(energyChartMarks(1000), [1000]);
      expect(energyChartMarks(4000), [1000, 2000, 3000, 4000]);
      expect(energyChartMarks(5000), [2000, 4000]);
      expect(energyChartMarks(7000), [2000, 4000, 6000]);
    });

    test('a fraction of the day picks the closest point', () {
      expect(energyPointAt(_afternoon, 0), 0);
      expect(energyPointAt(_afternoon, 6 / 24), 6);
      expect(energyPointAt(_afternoon, 6.4 / 24), 6);
      expect(energyPointAt(_afternoon, 1), _afternoon.points.length - 1);
      expect(energyPointAt(_afternoon, -3), 0);
    });
  });

  group('the readout', () {
    testWidgets('starts at now with the range of the day so far', (
      tester,
    ) async {
      await _pump(tester);
      final last = _afternoon.points.last.day;

      expect(
        _text(tester, EnergyThroughKeys.by),
        _l10n(tester).energyThroughByNow('14:30'),
      );
      expect(
        _text(tester, EnergyThroughKeys.range),
        _rangeText(tester, last.range),
      );
      expect(
        _text(tester, EnergyThroughKeys.parts),
        _l10n(tester).energyThroughParts(
          _format(tester).integer(energyPartShown(last.base)),
          _format(tester).integer(energyPartShown(last.steps)),
          '310',
        ),
      );
    });

    testWidgets('a tap on an hour shows the day as it stood then', (
      tester,
    ) async {
      await _pump(tester);

      await _tapHour(tester, 9);
      final then = _afternoon.points[9].day;

      expect(
        _text(tester, EnergyThroughKeys.by),
        _l10n(tester).energyThroughBy('09:00'),
      );
      expect(
        _text(tester, EnergyThroughKeys.range),
        _rangeText(tester, then.range),
      );
      expect(_text(tester, EnergyThroughKeys.parts), contains(' 0'));
    });

    testWidgets('a tap past now picks now', (tester) async {
      await _pump(tester);
      await _tapHour(tester, 9);

      await _tapHour(tester, 22);

      expect(
        _text(tester, EnergyThroughKeys.by),
        _l10n(tester).energyThroughByNow('14:30'),
      );
    });

    testWidgets('an early hour under the floor says the day was starting', (
      tester,
    ) async {
      await _pump(tester);

      await _tapHour(tester, 0);

      expect(_afternoon.points.first.day.range.low, lessThan(energyRowFloor));
      expect(
        _text(tester, EnergyThroughKeys.range),
        _l10n(tester).energyRowStarting,
      );
    });

    testWidgets('a pick of now follows a later day', (tester) async {
      await _pump(tester);
      await _pump(tester, curve: _curveAt(_at(16, 45)));

      expect(
        _text(tester, EnergyThroughKeys.by),
        _l10n(tester).energyThroughByNow('16:45'),
      );
    });

    testWidgets('a picked hour stays when the day is computed again', (
      tester,
    ) async {
      await _pump(tester);
      await _tapHour(tester, 9);
      await _pump(tester, curve: _curveAt(_at(16, 45)));

      expect(
        _text(tester, EnergyThroughKeys.by),
        _l10n(tester).energyThroughBy('09:00'),
      );
    });
  });

  group('a screen reader', () {
    testWidgets('steps back and forward through the hours', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final chart = find.semantics.byLabel(
        _l10n(tester).energyThroughSemantics,
      );

      tester.semantics.performAction(chart, SemanticsAction.decrease);
      await tester.pump();
      expect(
        _text(tester, EnergyThroughKeys.by),
        _l10n(tester).energyThroughBy('14:00'),
      );

      tester.semantics.performAction(chart, SemanticsAction.increase);
      await tester.pump();
      expect(
        _text(tester, EnergyThroughKeys.by),
        _l10n(tester).energyThroughByNow('14:30'),
      );
      handle.dispose();
    });
  });

  group('layout', () {
    for (final layout in layoutMatrix()) {
      testWidgets('fits $layout', (tester) async {
        await _pump(
          tester,
          locale: layout.locale,
          textScaler: layout.textScaler,
          brightness: layout.brightness,
        );

        expect(find.byKey(EnergyThroughKeys.card), findsOneWidget);
      });
    }

    for (final scale in [1.6, 2.0]) {
      for (final locale in AppLocales.supported) {
        testWidgets('fits ${scale}x in $locale', (tester) async {
          await _pump(
            tester,
            locale: locale,
            textScaler: TextScaler.linear(scale),
          );

          expect(find.byKey(EnergyThroughKeys.card), findsOneWidget);
        });
      }
    }
  });
  group('the usual day', () {
    List<double> level(double total) => [
      for (var hour = 0; hour <= 24; hour++) total * hour / 24,
    ];

    double nowTotal() => _afternoon.points.last.day.total;

    testWidgets('without it there is no sentence', (tester) async {
      await _pump(tester);

      expect(find.byKey(EnergyThroughKeys.usual), findsNothing);
      expect(find.text(_l10n(tester).energyLegendUsual), findsNothing);
    });

    testWidgets('says how much more than usual by this time', (tester) async {
      final usual = level((nowTotal() - 230) * 24 / 14.5);
      await _pump(tester, usual: usual);

      expect(
        energyUsualDifference(_afternoon, _afternoon.points.last, usual),
        250,
      );
      expect(
        tester.widget<BodyText>(find.byKey(EnergyThroughKeys.usual)).text,
        _l10n(tester).energyUsualMore('250'),
      );
      expect(find.text(_l10n(tester).energyLegendUsual), findsOneWidget);
    });

    testWidgets('says how much less than usual by this time', (tester) async {
      await _pump(tester, usual: level((nowTotal() + 420) * 24 / 14.5));

      expect(
        tester.widget<BodyText>(find.byKey(EnergyThroughKeys.usual)).text,
        _l10n(tester).energyUsualLess('400'),
      );
    });

    testWidgets('a small difference reads as about the same', (tester) async {
      await _pump(tester, usual: level((nowTotal() + 20) * 24 / 14.5));

      expect(
        tester.widget<BodyText>(find.byKey(EnergyThroughKeys.usual)).text,
        _l10n(tester).energyUsualSame,
      );
    });

    testWidgets('the sentence follows the picked hour', (tester) async {
      final usual = level(4800);
      await _pump(tester, usual: usual);

      await _tapHour(tester, 9);
      await tester.pump();
      final index = energyPointNear(_afternoon, _at(9));
      final difference = energyUsualDifference(
        _afternoon,
        _afternoon.points[index],
        usual,
      )!;

      expect(difference, isNot(0));
      expect(
        tester.widget<BodyText>(find.byKey(EnergyThroughKeys.usual)).text,
        contains(_format(tester).integer(difference.abs())),
      );
    });

    testWidgets('no sentence while the picked hour is under the floor', (
      tester,
    ) async {
      await _pump(tester, usual: level(2400));

      await _tapHour(tester, 0);
      await tester.pump();

      expect(find.byKey(EnergyThroughKeys.usual), findsNothing);
    });

    testWidgets('a day that is not 24 hours long shows no usual day', (
      tester,
    ) async {
      final short = (
        from: _afternoon.from,
        to: _afternoon.to.subtract(const Duration(hours: 1)),
        points: _afternoon.points,
      );
      await _pump(tester, curve: short, usual: level(2400));

      expect(find.byKey(EnergyThroughKeys.usual), findsNothing);
      expect(find.text(_l10n(tester).energyLegendUsual), findsNothing);
    });

    test('the axis rises to hold the usual day', () {
      expect(energyChartTop(_afternoon), 3000);
      expect(energyChartTop(_afternoon, usual: level(3600)), 4000);
    });

    for (final locale in AppLocales.supported) {
      testWidgets('fits 2.0x in $locale', (tester) async {
        await _pump(
          tester,
          usual: level(3000),
          locale: locale,
          textScaler: const TextScaler.linear(2),
        );

        expect(find.byKey(EnergyThroughKeys.usual), findsOneWidget);
      });
    }
  });
}
