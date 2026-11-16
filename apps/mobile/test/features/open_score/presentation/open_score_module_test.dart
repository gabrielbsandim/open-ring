import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/modules_offer_screen.dart';
import 'package:open_ring/features/open_score/presentation/open_score_module_screen.dart';

import '../../../helpers/layout_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  Set<ModuleId> modules,
  Locale locale,
) => pumpScaled(
  tester,
  screenHost(screen),
  textScaler: const TextScaler.linear(2),
  brightness: Brightness.light,
  locale: locale,
  overrides: [
    moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  ],
  size: const Size(360, 12000),
);

void main() {
  testWidgets('the module screen lists the Overall and promises nothing', (
    tester,
  ) async {
    await _pump(tester, const OpenScoreModuleScreen(), {
      ModuleId.openScore,
    }, const Locale('en'));

    expect(find.textContaining('The Overall, your base'), findsOneWidget);
    expect(find.textContaining('The Overall also reads'), findsOneWidget);
    expect(find.textContaining('More to come'), findsNothing);
  });

  for (final locale in const [Locale('de'), Locale('ru'), Locale('ja')]) {
    for (final modules in const [
      <ModuleId>{},
      {ModuleId.openScore},
    ]) {
      testWidgets('the Open Score detail fits at twice the text size, $locale, '
          '${modules.length} on', (tester) async {
        await _pump(tester, const OpenScoreModuleScreen(), modules, locale);

        expect(find.byKey(OpenScoreModuleKeys.toggle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the onboarding offer fits at twice the text size, $locale', (
      tester,
    ) async {
      await _pump(tester, const ModulesOfferScreen(), const {}, locale);

      expect(find.byKey(ModulesOfferKeys.openScore), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
