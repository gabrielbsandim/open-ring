import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/core/widgets/open_ring_logo.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../helpers/ble_fakes.dart';
import '../helpers/in_memory_theme_mode_store.dart';
import '../helpers/onboarding_fakes.dart';
import '../helpers/ring_fakes.dart';
import '../helpers/settings_fakes.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  Locale? locale,
  InMemoryThemeModeStore? store,
}) async {
  if (locale != null) {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeModeStoreProvider.overrideWithValue(
          store ?? InMemoryThemeModeStore(),
        ),
        onboardingStoreProvider.overrideWithValue(
          InMemoryOnboardingStore(completed: true),
        ),
        ...bleOverrides(),
        ...ringOverrides(),
      ],
      child: const OpenRingApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Brightness brightnessOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(AppNavigationBar))).brightness;

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(RingScreen.settingsKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Today with the five tabs', (tester) async {
    await pumpApp(tester, locale: const Locale('en', 'US'));

    expect(find.byType(TodayScreen), findsOneWidget);
    for (final tab in AppTab.values) {
      expect(find.byKey(AppNavigationBar.destinationKey(tab)), findsOneWidget);
    }
    for (final label in ['Today', 'Sleep', 'Heart', 'Activity', 'Ring']) {
      expect(
        find.descendant(
          of: find.byType(AppNavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('a tab tap shows that tab', (tester) async {
    await pumpApp(tester, locale: const Locale('en', 'US'));

    await tester.tap(find.byIcon(Icons.bedtime_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(SleepScreen), findsOneWidget);
    expect(find.textContaining('Wear your ring to bed'), findsOneWidget);
  });

  testWidgets('Ring opens settings inside its tab', (tester) async {
    await pumpApp(tester, locale: const Locale('en', 'US'));

    await tester.tap(find.byType(OpenRingMark).last);
    await tester.pumpAndSettle();
    expect(find.byType(RingScreen), findsOneWidget);

    await tester.tap(find.byKey(RingScreen.settingsKey));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });

  testWidgets('the Ring tab mark takes the nav bar colors', (tester) async {
    await pumpApp(tester, locale: const Locale('en', 'US'));

    OpenRingMark mark() => tester.widget<OpenRingMark>(
      find.descendant(
        of: find.byKey(AppNavigationBar.destinationKey(AppTab.ring)),
        matching: find.byType(OpenRingMark),
      ),
    );
    final colors = AppColors.of(tester.element(find.byType(AppNavigationBar)));

    expect(mark().size, 24);
    expect(mark().color, colors.textLabel);

    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
    await tester.pumpAndSettle();

    expect(mark().color, colors.textPrimary);
  });

  testWidgets('follows the system brightness by default', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester, locale: const Locale('en'));

    expect(brightnessOf(tester), Brightness.dark);
  });

  testWidgets('a saved mode wins over the system brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(
      tester,
      locale: const Locale('en'),
      store: InMemoryThemeModeStore(ThemeMode.light),
    );

    expect(brightnessOf(tester), Brightness.light);
  });

  testWidgets('Settings switches the theme and saves the choice', (
    tester,
  ) async {
    final store = InMemoryThemeModeStore();
    await pumpApp(tester, locale: const Locale('en'), store: store);
    await openSettings(tester);
    await reveal(
      tester,
      find.byKey(SettingsScreen.themeModeKey(ThemeMode.dark)),
    );

    expect(find.text('Follow system'), findsOneWidget);
    await tester.tap(find.byKey(SettingsScreen.themeModeKey(ThemeMode.dark)));
    await tester.pumpAndSettle();

    expect(brightnessOf(tester), Brightness.dark);
    expect(store.saved, ThemeMode.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(brightnessOf(tester), Brightness.light);
    expect(store.saved, ThemeMode.light);
  });

  testWidgets('Settings reads the theme options in German', (tester) async {
    await pumpApp(tester, locale: const Locale('de', 'DE'));
    await openSettings(tester);
    await reveal(
      tester,
      find.byKey(SettingsScreen.themeModeKey(ThemeMode.dark)),
    );

    expect(find.text('Erscheinungsbild'), findsOneWidget);
    expect(find.text('Systemeinstellung verwenden'), findsOneWidget);
    expect(find.text('Hell'), findsOneWidget);
    expect(find.text('Dunkel'), findsOneWidget);
  });

  testWidgets('a Brazilian device reads Portuguese', (tester) async {
    await pumpApp(tester, locale: const Locale('pt', 'BR'));

    expect(find.text('Hoje'), findsWidgets);
    expect(find.text('Anel'), findsOneWidget);
  });

  testWidgets('a Portuguese device in Portugal reads European Portuguese', (
    tester,
  ) async {
    await pumpApp(tester, locale: const Locale('pt', 'PT'));

    expect(find.textContaining('Emparelhe o seu anel'), findsOneWidget);
    expect(find.text('Anel'), findsOneWidget);
  });

  testWidgets('an unsupported device language reads English', (tester) async {
    await pumpApp(tester, locale: const Locale('ar', 'EG'));

    expect(find.textContaining('Pair your ring'), findsOneWidget);
    expect(find.text('Ring'), findsOneWidget);
  });

  testWidgets('the app locale resolves an unsupported system language to '
      'English', (tester) async {
    await pumpApp(tester, locale: const Locale('ko', 'KR'));

    final context = tester.element(find.byType(TodayScreen));
    expect(Localizations.localeOf(context), const Locale('en'));
  });

  testWidgets('a supported second system language wins over English', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [
      Locale('ko', 'KR'),
      Locale('fr', 'FR'),
    ];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester);

    final context = tester.element(find.byType(TodayScreen));
    expect(Localizations.localeOf(context), const Locale('fr'));
  });

  testWidgets('Settings offers no language choice', (tester) async {
    await pumpApp(tester, locale: const Locale('en'));
    await openSettings(tester);
    final texts = await shownTexts(tester);

    expect(texts, contains('About'));
    expect(texts, isNot(contains('Language')));
    expect(texts, isNot(contains('Follow system language')));
  });
}
