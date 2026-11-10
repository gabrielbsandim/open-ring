import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

Future<void> pumpApp(WidgetTester tester, {Locale? locale}) async {
  if (locale != null) {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
  await tester.pumpWidget(const ProviderScope(child: OpenRingApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Today with the five tabs', (tester) async {
    await pumpApp(tester, locale: const Locale('en', 'US'));

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final label in ['Today', 'Sleep', 'Heart', 'Activity', 'Ring']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
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

    await tester.tap(find.byIcon(Icons.radio_button_unchecked_rounded).last);
    await tester.pumpAndSettle();
    expect(find.byType(RingScreen), findsOneWidget);

    await tester.tap(find.byKey(RingScreen.settingsKey));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a Brazilian device reads Portuguese', (tester) async {
    await pumpApp(tester, locale: const Locale('pt', 'BR'));

    expect(find.text('Hoje'), findsWidgets);
    expect(find.text('Anel'), findsOneWidget);
  });

  group('resolveLocale', () {
    test('any Portuguese variant opens Portuguese', () {
      expect(
        OpenRingApp.resolveLocale(const Locale('pt', 'PT'), const []),
        const Locale('pt'),
      );
    });

    test('every other language, or none, opens English', () {
      expect(
        OpenRingApp.resolveLocale(const Locale('es'), const []),
        const Locale('en'),
      );
      expect(OpenRingApp.resolveLocale(null, const []), const Locale('en'));
    });
  });
}
