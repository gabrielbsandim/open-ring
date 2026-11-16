import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/presentation/effort_week_tile.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../../helpers/layout_harness.dart';

EffortWeek _week({double points = 87.4, int strengthDays = 1}) => EffortWeek(
  monday: const LocalDate(2026, 11, 16),
  points: points,
  strengthDays: strengthDays,
);

List<Override> _overrides({
  Set<ModuleId> modules = const {ModuleId.effort},
  EffortWeek? week,
  bool fails = false,
}) => [
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  effortWeekProvider.overrideWith((ref) async {
    if (fails) throw StateError('no week');
    return week ?? _week();
  }),
];

Future<void> _pump(
  WidgetTester tester, {
  Set<ModuleId> modules = const {ModuleId.effort},
  EffortWeek? week,
  bool fails = false,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(
    const Scaffold(body: SingleChildScrollView(child: EffortWeekTileSlot())),
  ),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: _overrides(modules: modules, week: week, fails: fails),
);

String _caption(WidgetTester tester, Key key) =>
    tester.widget<CaptionText>(find.byKey(key)).text;

void main() {
  group('the gate', () {
    testWidgets('with Effort off there is no tile', (tester) async {
      await _pump(tester, modules: const {ModuleId.openScore});

      expect(find.byKey(EffortWeekTileKeys.tile), findsNothing);
    });

    testWidgets('when the week fails there is no tile', (tester) async {
      await _pump(tester, fails: true);

      expect(find.byKey(EffortWeekTileKeys.tile), findsNothing);
    });
  });

  group('the tile', () {
    testWidgets('prints the rounded points of the week and the target', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        tester.widget<Text>(find.byKey(EffortWeekTileKeys.points)).data,
        '87',
      );
      expect(
        _caption(tester, EffortWeekTileKeys.target),
        'of 150 Effort Points',
      );
      expect(_caption(tester, EffortWeekTileKeys.note), 'This week');
    });

    testWidgets('an empty week prints zero, not nothing', (tester) async {
      await _pump(tester, week: _week(points: 0, strengthDays: 0));

      expect(
        tester.widget<Text>(find.byKey(EffortWeekTileKeys.points)).data,
        '0',
      );
    });

    testWidgets('is one button a screen reader can open', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final data = tester
          .getSemantics(find.byKey(EffortWeekTileKeys.tile))
          .getSemanticsData();

      expect(data.label, 'Effort, This week: 87 of 150 Effort Points');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });
  });

  group('layout', () {
    for (final locale in AppLocales.supported) {
      for (final brightness in Brightness.values) {
        testWidgets('fits 2x in $locale, ${brightness.name}', (tester) async {
          await _pump(
            tester,
            week: _week(points: 1234),
            locale: locale,
            textScaler: const TextScaler.linear(2),
            brightness: brightness,
          );

          expect(find.byKey(EffortWeekTileKeys.tile), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
