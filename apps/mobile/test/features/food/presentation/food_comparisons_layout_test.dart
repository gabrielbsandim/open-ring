import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/food_comparisons.dart';
import 'package:open_ring/features/food/presentation/food_comparisons_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

final _now = DateTime(2026, 11, 17, 21);

FoodComparisonsView _layoutView() => const FoodComparisonsView(
  firstNight: LocalDate(2026, 8, 18),
  lastNight: LocalDate(2026, 11, 15),
  updatedMonday: LocalDate(2026, 11, 16),
  items: [
    FoodComparisonItem(
      link: FoodLink.alcoholThreeOrMore,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: true,
      lead: LinkPattern(pairs: 12, mean: 5.1, low: 1.6, high: 8.6),
      also: LinkPattern(pairs: 12, mean: -19.5, low: -25.2, high: -13.4),
      leadPairs: [],
    ),
    FoodComparisonItem(
      link: FoodLink.lateLastMeal,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: false,
      lead: LinkPattern(pairs: 16, mean: 4.2, low: 1.6, high: 6.8),
      also: LinkCollecting(pairs: 9, minimum: 14),
      leadPairs: [],
    ),
    FoodComparisonItem(
      link: FoodLink.caffeineAfter14,
      leadOutcome: NightOutcome.onset,
      alsoOutcome: NightOutcome.heartRate,
      alcoholLink: false,
      lead: LinkNoClearDifference(
        pairs: 16,
        mean: -0.3,
        low: -13.6,
        high: 13.1,
      ),
      also: LinkNoClearDifference(pairs: 16, mean: 0.4, low: -1.1, high: 1.9),
      leadPairs: [],
    ),
    FoodComparisonItem(
      link: FoodLink.heavyDinner,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: false,
      lead: LinkCollecting(pairs: 9, minimum: 14),
      also: LinkCollecting(pairs: 9, minimum: 14),
      leadPairs: [],
    ),
    FoodComparisonItem(
      link: FoodLink.alcoholOneToTwo,
      leadOutcome: NightOutcome.heartRate,
      alsoOutcome: NightOutcome.hrv,
      alcoholLink: true,
      lead: LinkCollecting(pairs: 7, minimum: 10),
      also: LinkCollecting(pairs: 7, minimum: 10),
      leadPairs: [],
    ),
  ],
  regularity: MealRegularity(
    completeDays: 14,
    firstMealSdMinutes: 68,
    weekendLaterMinutes: 130,
  ),
);

void main() {
  group('FoodComparisonsScreen layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodComparisonsScreen fits without overflow at $c', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(c.locale);
        await pumpScaled(
          tester,
          screenHost(const FoodComparisonsScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: [
            moduleStoreProvider.overrideWithValue(
              InMemoryModuleStore({ModuleId.food}),
            ),
            clockProvider.overrideWithValue(() => _now),
            foodComparisonsProvider.overrideWith((ref) async => _layoutView()),
          ],
        );

        expect(find.byKey(FoodComparisonsKeys.lead), findsOneWidget);
        await expectNoLayoutOverflow(() async {
          final scrollable = find.byType(Scrollable).first;
          for (final key in [
            FoodComparisonsKeys.card(FoodLink.caffeineAfter14),
            FoodComparisonsKeys.card(FoodLink.heavyDinner),
            FoodComparisonsKeys.regularityCard,
            FoodComparisonsKeys.formulaLink,
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(key),
              140,
              scrollable: scrollable,
            );
            await tester.pumpAndSettle();
          }
        });
        expect(find.text(l10n.formulaLink), findsOneWidget);
      });
    }
  });
}
