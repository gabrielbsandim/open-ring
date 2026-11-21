import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/food_comparisons.dart';
import 'package:open_ring/features/food/presentation/food_comparison_detail_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

final _now = DateTime(2026, 11, 17, 21);

FoodComparisonsView _detailLayoutView() => FoodComparisonsView(
  firstNight: const LocalDate(2026, 8, 18),
  lastNight: const LocalDate(2026, 11, 15),
  updatedMonday: const LocalDate(2026, 11, 16),
  items: [
    FoodComparisonItem(
      link: FoodLink.alcoholThreeOrMore,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: true,
      lead: const LinkPattern(pairs: 12, mean: 5.1, low: 1.6, high: 8.6),
      also: const LinkPattern(pairs: 12, mean: -19.5, low: -25.2, high: -13.4),
      leadPairs: const [
        FoodComparisonPair(
          exposedDay: LocalDate(2026, 10, 31),
          controlDay: LocalDate(2026, 10, 30),
          exposedHeartRate: 64,
          controlHeartRate: 57,
          diff: 7,
        ),
        FoodComparisonPair(
          exposedDay: LocalDate(2026, 11, 14),
          controlDay: LocalDate(2026, 11, 13),
          exposedHeartRate: 66,
          controlHeartRate: 59,
          diff: 7,
        ),
      ],
      leadSd: 2.8,
      leadT99: t99(11),
    ),
  ],
  regularity: const RegularityCollecting(completeDays: 6, minimum: 10),
);

void main() {
  group('FoodComparisonDetailScreen layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodComparisonDetailScreen fits without overflow at $c', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(c.locale);
        await pumpScaled(
          tester,
          screenHost(
            const FoodComparisonDetailScreen(link: FoodLink.alcoholThreeOrMore),
          ),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: [
            moduleStoreProvider.overrideWithValue(
              InMemoryModuleStore({ModuleId.food}),
            ),
            clockProvider.overrideWithValue(() => _now),
            foodComparisonsProvider.overrideWith(
              (ref) async => _detailLayoutView(),
            ),
          ],
        );

        await expectNoLayoutOverflow(() async {
          final scrollable = find.byType(Scrollable).first;
          for (final key in const [
            FoodComparisonDetailKeys.lead,
            FoodComparisonDetailKeys.alsoCard,
            FoodComparisonDetailKeys.pairsCard,
            FoodComparisonDetailKeys.ruleCard,
            FoodComparisonDetailKeys.cannotCard,
            FoodComparisonDetailKeys.formulaLink,
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(key),
              140,
              scrollable: scrollable,
            );
            await tester.pumpAndSettle();
            expect(find.byKey(key), findsOneWidget);
          }
        });
        expect(find.text(l10n.formulaLink), findsOneWidget);
      });
    }
  });
}
