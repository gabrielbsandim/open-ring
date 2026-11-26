import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';
import 'package:open_ring/features/trajectory/presentation/what_if_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../support/what_if_fixtures.dart';
import 'trajectory_screen_fixtures.dart';

const _tall = Size(360, 4000);

Future<void> _pump(
  WidgetTester tester, {
  TrajectoryView? view,
  double typical = 8700,
  bool hidden = false,
  EnergyGate gate = EnergyGate.on,
  bool noSteps = false,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  Size size = _tall,
}) => pumpScaled(
  tester,
  screenHost(const WhatIfScreen()),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: locale,
  size: size,
  overrides: whatIfOverrides(
    view: view,
    typical: typical,
    hidden: hidden,
    gate: gate,
    levers: noSteps ? leversWith(validDays: 31) : null,
  ),
);

String _textOf(WidgetTester tester, Finder within) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: within, matching: find.byType(Text)),
  ))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join(' | ');

String _all(WidgetTester tester) => _textOf(tester, find.byType(WhatIfScreen));

final String _clamped = lookupAppLocalizations(const Locale('en'))
    .trajectoryWhatIfClamped('10,901');

void main() {
  group('TR10b acceptance 1: the Ready scenario numbers', () {
    testWidgets('+2000 is selected and shows 1.48 and 0.49', (tester) async {
      await _pump(tester);

      expect(find.byKey(WhatIfKeys.step2000), findsOneWidget);
      final weight = _textOf(tester, find.byKey(WhatIfKeys.weight));
      expect(weight, contains('1.48'));
      expect(weight, contains('0.49'));
      expect(find.byKey(WhatIfKeys.cohort), findsOneWidget);
      expect(find.byKey(WhatIfKeys.noScenario), findsNothing);
      expect(find.byKey(WhatIfKeys.noSteps), findsNothing);
    });
  });

  group('TR10b acceptance 2: hidden numbers', () {
    testWidgets('no kg and no kcal, the weight row reads in words', (
      tester,
    ) async {
      await _pump(tester, hidden: true);

      final all = _all(tester);
      expect(all, isNot(contains('kg')));
      expect(all, isNot(contains('kcal')));
      expect(all, isNot(contains('0.49')));
      expect(find.byKey(WhatIfKeys.weight), findsOneWidget);
      expect(_textOf(tester, find.byKey(WhatIfKeys.weight)).trim(), isNotEmpty);
    });

    testWidgets('hidden with Energy on still shows no kcal', (tester) async {
      await _pump(tester, hidden: true);

      expect(find.textContaining('kcal'), findsNothing);
    });
  });

  group('TR10b acceptance 3: refusals', () {
    for (final reason in TrajectoryRefusal.values) {
      testWidgets('${reason.name} shows only the refusal', (tester) async {
        await _pump(tester, view: TrajectoryRefused(reason));

        expect(find.byKey(WhatIfKeys.weight), findsNothing);
        expect(find.byKey(WhatIfKeys.cohort), findsNothing);
        expect(find.byKey(WhatIfKeys.step2000), findsNothing);
        expect(find.textContaining('kcal'), findsNothing);
        expect(find.byKey(TrajectoryKeys.refused), findsOneWidget);
      });
    }
  });

  group('TR10b acceptance 4: Building and Guard', () {
    final views = <String, TrajectoryView>{
      'guard': guardView,
      'building': const TrajectoryBuilding(null),
    };
    for (final MapEntry(:key, :value) in views.entries) {
      testWidgets('$key shows cohort and the no scenario line, no kg', (
        tester,
      ) async {
        await _pump(tester, view: value);

        expect(find.byKey(WhatIfKeys.cohort), findsOneWidget);
        expect(find.byKey(WhatIfKeys.noScenario), findsOneWidget);
        expect(find.byKey(WhatIfKeys.weight), findsNothing);
        expect(find.textContaining('kg'), findsNothing);
        expect(find.textContaining('kcal'), findsNothing);
        expect(find.byKey(WhatIfKeys.step2000), findsOneWidget);
      });
    }
  });

  group('TR10b acceptance 5: no steps trend', () {
    testWidgets('the screen names the valid day count', (tester) async {
      await _pump(tester, noSteps: true);

      expect(find.byKey(WhatIfKeys.noSteps), findsOneWidget);
      expect(_textOf(tester, find.byKey(WhatIfKeys.noSteps)), contains('31'));
      expect(find.byKey(WhatIfKeys.weight), findsNothing);
      expect(find.byKey(WhatIfKeys.cohort), findsNothing);
    });
  });

  group('TR10b acceptance 6: Energy gate', () {
    for (final gate in EnergyGate.values) {
      testWidgets('${gate.name} shows kg and never kcal', (tester) async {
        await _pump(tester, gate: gate);

        final weight = _textOf(tester, find.byKey(WhatIfKeys.weight));
        expect(weight, contains('0.49'));
        expect(weight, contains('kg'));
        expect(find.textContaining('kcal'), findsNothing);
      });
    }
  });

  group('TR10b acceptance 7: clamped typical', () {
    testWidgets('a typical above 10901 reads differently from one below', (
      tester,
    ) async {
      await _pump(tester);
      final below = _textOf(tester, find.byKey(WhatIfKeys.cohort));

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, typical: 11500);
      final above = _textOf(tester, find.byKey(WhatIfKeys.cohort));

      expect(above, isNot(below));
      expect(find.byKey(WhatIfKeys.cohort), findsOneWidget);
    });
  });

  group('TR10b acceptance 8: the step size is screen state', () {
    testWidgets('+1000 and +3000 change the numbers, +2000 restores them', (
      tester,
    ) async {
      await _pump(tester);
      String weight() => _textOf(tester, find.byKey(WhatIfKeys.weight));
      expect(weight(), contains('1.48'));

      await tester.tap(find.byKey(WhatIfKeys.step1000));
      await tester.pumpAndSettle();
      expect(weight(), contains('0.74'));
      expect(weight(), isNot(contains('1.48')));
      expect(weight(), isNot(contains('0.49')));

      await tester.tap(find.byKey(WhatIfKeys.step3000));
      await tester.pumpAndSettle();
      expect(weight(), contains('2.22'));
      expect(weight(), isNot(contains('1.48')));

      await tester.tap(find.byKey(WhatIfKeys.step2000));
      await tester.pumpAndSettle();
      expect(weight(), contains('1.48'));
      expect(weight(), contains('0.49'));
    });

    testWidgets('the choice is not kept after the screen is rebuilt', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(WhatIfKeys.step3000));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await _pump(tester);

      expect(_textOf(tester, find.byKey(WhatIfKeys.weight)), contains('1.48'));
    });
  });

  group('TR10b acceptance 9: no overflow', () {
    for (final layout in layoutMatrix()) {
      testWidgets('ready at $layout', (tester) async {
        await _pump(
          tester,
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
          size: phoneSize,
        );
        await expectNoLayoutOverflow(() async {
          for (final key in [
            WhatIfKeys.step1000,
            WhatIfKeys.step3000,
            WhatIfKeys.step2000,
          ]) {
            final scrollable = find.byType(Scrollable).first;
            await tester.drag(scrollable, const Offset(0, 5000));
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byKey(key),
              200,
              scrollable: scrollable,
            );
            await tester.tap(find.byKey(key));
            await tester.pumpAndSettle();
          }
          await tester.scrollUntilVisible(
            find.byKey(WhatIfKeys.cohort),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        });

        expect(find.byKey(WhatIfKeys.cohort), findsOneWidget);
      });
    }

    for (final locale in layoutLocales) {
      testWidgets('other states at 2.0x in $locale', (tester) async {
        final states = <Future<void> Function()>[
          () => _pump(
            tester,
            view: guardView,
            scale: 2,
            locale: locale,
            size: phoneSize,
          ),
          () => _pump(
            tester,
            noSteps: true,
            scale: 2,
            locale: locale,
            size: phoneSize,
          ),
          () => _pump(
            tester,
            hidden: true,
            typical: 11500,
            scale: 2,
            locale: locale,
            size: phoneSize,
          ),
          () => _pump(
            tester,
            view: const TrajectoryRefused(TrajectoryRefusal.pregnancy),
            scale: 2,
            locale: locale,
            size: phoneSize,
          ),
        ];
        for (final state in states) {
          await tester.pumpWidget(const SizedBox());
          await state();
          await expectNoLayoutOverflow(() async {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -3000),
            );
            await tester.pumpAndSettle();
          });
        }
      });
    }
  });

  group('TR10b review round 1', () {
    String cohort(WidgetTester tester) =>
        _textOf(tester, find.byKey(WhatIfKeys.cohort));

    testWidgets('F3: the clamped sentence shows only when clamped', (
      tester,
    ) async {
      await _pump(tester);
      expect(cohort(tester), isNot(contains(_clamped)));

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, typical: 11500);
      expect(cohort(tester), contains(_clamped));
    });

    testWidgets('F1: typical 12000 names no group above 10,901', (
      tester,
    ) async {
      await _pump(tester, typical: 12000);

      final text = cohort(tester);
      expect(text, contains(_clamped));
      expect(text, isNot(contains('12,000')));
      expect(text, isNot(contains('Groups walking')));
    });

    testWidgets('F1: typical 9500 plus 2000 names 10,901 and 9,500', (
      tester,
    ) async {
      await _pump(tester, typical: 9500);

      final text = cohort(tester);
      expect(
        text,
        contains(
          lookupAppLocalizations(const Locale('en'))
              .trajectoryWhatIfGroups('10,901', '9,500'),
        ),
      );
      expect(text, contains(_clamped));
      expect(text, isNot(contains('11,500')));
    });

    testWidgets('F5: Retry recovers from a failed weigh-in read', (
      tester,
    ) async {
      var reads = 0;
      await pumpScaled(
        tester,
        screenHost(const WhatIfScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.light,
        locale: const Locale('en'),
        size: _tall,
        overrides: whatIfOverrides(
          weighIns: () async {
            reads++;
            if (reads == 1) throw StateError('weigh-ins unreadable');
            return const [];
          },
          read: (ref) async {
            await ref.watch(weightSummaryProvider.future);
            return readyView();
          },
        ),
      );
      expect(find.byKey(TrajectoryKeys.retry), findsOneWidget);

      await tester.tap(find.byKey(TrajectoryKeys.retry));
      await tester.pumpAndSettle();

      expect(find.byKey(WhatIfKeys.cohort), findsOneWidget);
    });
  });
}
