import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/presentation/food_formula_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

void main() {
  group('FoodFormulaScreen layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodFormulaScreen fits without overflow at $c', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(c.locale);
        await pumpScaled(
          tester,
          screenHost(const FoodFormulaScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
        );

        expect(find.byKey(FoodFormulaKeys.intro), findsOneWidget);
        await expectNoLayoutOverflow(() async {
          final scrollable = find.byType(Scrollable).first;
          for (final key in const [
            FoodFormulaKeys.comparisons,
            FoodFormulaKeys.plate,
            FoodFormulaKeys.ours,
            FoodFormulaKeys.unchecked,
            FoodFormulaKeys.estimate,
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(key),
              140,
              scrollable: scrollable,
            );
            await tester.pumpAndSettle();
          }
        });
        expect(find.text(l10n.metricEstimateNote), findsOneWidget);
      });
    }
  });
}
