import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_week.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const _today = LocalDate(2026, 11, 10);
final _asOf = DateTime.utc(2026, 11, 10, 14, 30);

EnergyDayEstimate _estimate(double steps, {double base = 2200}) =>
    EnergyDayEstimate(resting: 1700, base: base, steps: steps, workouts: 0);

List<EnergyWeekDay> _week(List<EnergyDayEstimate?> days) => [
  for (final (index, day) in days.indexed)
    (date: _today.addDays(index - days.length + 1), day: day),
];

final List<EnergyWeekDay> _full = _week([
  _estimate(100),
  _estimate(200),
  null,
  _estimate(300),
  _estimate(400),
  _estimate(600),
  _estimate(50, base: 1300),
]);

Future<void> _pump(
  WidgetTester tester, {
  List<EnergyWeekDay>? days,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(
    Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: EnergyWeek(days: days ?? _full, asOf: _asOf),
      ),
    ),
  ),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: const [],
);

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(EnergyWeek));

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(_context(tester));

MetricFormat _format(WidgetTester tester) => MetricFormat.of(_context(tester));

String _text(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data!,
      final CaptionText text => text.text,
      final BodyText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

String _kcal(WidgetTester tester, EnergyRange range) {
  final format = _format(tester);
  return _l10n(tester).energyKcal(
    _l10n(tester)
        .energyRowRange(format.integer(range.low), format.integer(range.high)),
  );
}

Future<void> _tapDay(WidgetTester tester, int index) async {
  final box = tester.getRect(find.byKey(EnergyWeekKeys.chart));
  const left = 40.0;
  const right = 8.0;
  final column = (box.width - left - right) / 7;
  await tester.tapAt(
    box.topLeft + Offset(left + column * (index + 0.5), box.height / 2),
  );
  await tester.pump();
}

void main() {
  group('the axis', () {
    test('the top is the first grid step above the highest range', () {
      expect(energyWeekTop(_full), 4000);
      expect(energyWeekTop(_week([null, null])), 1000);
    });
  });

  group('the usual day', () {
    test('is the mean of the past days on record, without today', () {
      expect(energyWeekUsual(_full), 2200 + (100 + 200 + 300 + 400 + 600) / 5);
    });

    test('is absent with fewer past days than the minimum', () {
      final days = _week([
        null,
        null,
        null,
        null,
        _estimate(100),
        _estimate(200),
        _estimate(300),
      ]);

      expect(energyWeekUsual(days), isNull);
    });

    testWidgets('shows as a range', (tester) async {
      await _pump(tester);

      expect(
        _text(tester, EnergyWeekKeys.usual),
        _kcal(tester, energyRange(2520, energyDayMargin)),
      );
    });

    testWidgets('is not shown without enough days', (tester) async {
      await _pump(
        tester,
        days: _week([null, null, null, null, null, _estimate(100), null]),
      );

      expect(find.byKey(EnergyWeekKeys.usual), findsNothing);
    });
  });

  group('the readout', () {
    testWidgets('starts on today with the time of the estimate', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        _text(tester, EnergyWeekKeys.day),
        '${_l10n(tester).tabToday}, 14:30',
      );
      expect(
        _text(tester, EnergyWeekKeys.range),
        _kcal(tester, _full.last.day!.range),
      );
      expect(
        _text(tester, EnergyWeekKeys.parts),
        _l10n(tester).energyThroughParts('1,300', '50', '0'),
      );
    });

    testWidgets('a tap on a bar shows that day', (tester) async {
      await _pump(tester);

      await _tapDay(tester, 1);

      expect(
        _text(tester, EnergyWeekKeys.day),
        _format(tester).date(_full[1].date),
      );
      expect(
        _text(tester, EnergyWeekKeys.range),
        _kcal(tester, _full[1].day!.range),
      );
    });

    testWidgets('a day with nothing on record says so and shows no number', (
      tester,
    ) async {
      await _pump(tester);

      await _tapDay(tester, 2);

      expect(
        _text(tester, EnergyWeekKeys.range),
        _l10n(tester).energyWeekNoData,
      );
      expect(find.byKey(EnergyWeekKeys.parts), findsNothing);
    });

    testWidgets('a today under the floor shows the starting line', (
      tester,
    ) async {
      await _pump(
        tester,
        days: _week([_estimate(100), _estimate(0, base: 20)]),
      );

      expect(
        _text(tester, EnergyWeekKeys.range),
        _l10n(tester).energyRowStarting,
      );
    });

    testWidgets('a picked day stays when the week is recomputed', (
      tester,
    ) async {
      await _pump(tester);
      await _tapDay(tester, 4);

      await _pump(tester, days: [..._full]);

      expect(
        _text(tester, EnergyWeekKeys.day),
        _format(tester).date(_full[4].date),
      );
    });
  });

  group('a screen reader', () {
    testWidgets('steps a day back and forward', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final chart = find.semantics.byLabel(_l10n(tester).energyWeekSemantics);

      tester.semantics.performAction(chart, SemanticsAction.decrease);
      await tester.pump();
      expect(
        _text(tester, EnergyWeekKeys.day),
        _format(tester).date(_full[5].date),
      );

      tester.semantics.performAction(chart, SemanticsAction.increase);
      await tester.pump();
      expect(
        _text(tester, EnergyWeekKeys.day),
        '${_l10n(tester).tabToday}, 14:30',
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

        expect(find.byKey(EnergyWeekKeys.card), findsOneWidget);
      });
    }

    for (final locale in AppLocales.supported) {
      testWidgets('fits 2.0x in $locale', (tester) async {
        await _pump(
          tester,
          locale: locale,
          textScaler: const TextScaler.linear(2),
        );

        expect(find.byKey(EnergyWeekKeys.card), findsOneWidget);
      });
    }
  });
}
