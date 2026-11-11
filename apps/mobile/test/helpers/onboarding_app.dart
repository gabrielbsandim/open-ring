import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';

import 'in_memory_theme_mode_store.dart';
import 'onboarding_fakes.dart';
import 'protocol_lab_fakes.dart';
import 'ring_fakes.dart';

// Tall enough that a whole onboarding page is built without scrolling.
const tallPhone = Size(400, 2400);

Future<ProviderContainer> pumpOnboardingApp(
  WidgetTester tester, {
  String? at,
  InMemoryOnboardingStore? store,
  List<Override>? overrides,
}) async {
  tester.view
    ..devicePixelRatio = 3
    ..physicalSize = tallPhone * 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = [const Locale('en')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeModeStoreProvider.overrideWithValue(InMemoryThemeModeStore()),
        onboardingStoreProvider.overrideWithValue(
          store ?? InMemoryOnboardingStore(),
        ),
        ...overrides ??
            [
              ...protocolLabOverrides(),
              ...ringOverrides(),
              ...onboardingOverrides(),
            ],
      ],
      child: const OpenRingApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(OpenRingApp)),
  );
  if (at == null) return container;
  container.read(appRouterProvider).go(at);
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder fieldOf(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(TextField));
