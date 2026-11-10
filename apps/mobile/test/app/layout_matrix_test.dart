import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../helpers/layout_harness.dart';

const screens = <String, Widget>{
  'Today': TodayScreen(),
  'Sleep': SleepScreen(),
  'Heart': HeartScreen(),
  'Activity': ActivityScreen(),
  'Ring': RingScreen(),
  'Settings': SettingsScreen(),
};

Future<void> pumpCase(WidgetTester tester, Widget widget, LayoutCase c) =>
    pumpScaled(
      tester,
      widget,
      textScaler: c.textScaler,
      brightness: c.brightness,
      locale: c.locale,
    );

Future<void> visitEveryTab(WidgetTester tester) async {
  for (final tab in AppTab.values) {
    await tester.tap(find.byKey(AppNavigationBar.destinationKey(tab)));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(RingScreen.settingsKey));
  await tester.pumpAndSettle();
}

double navBarHeight(WidgetTester tester) =>
    tester.getSize(find.byType(AppNavigationBar)).height;

void main() {
  for (final MapEntry(key: name, value: screen) in screens.entries) {
    group('$name screen', () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpCase(tester, screenHost(screen), c);

          expect(find.byWidget(screen), findsOneWidget);
          expect(
            Theme.of(tester.element(find.byWidget(screen))).brightness,
            c.brightness,
          );
        });
      }
    });
  }

  group('shell', () {
    for (final c in layoutMatrix()) {
      testWidgets('every tab lays out without overflow at $c', (tester) async {
        await pumpCase(tester, const OpenRingApp(), c);

        await expectNoLayoutOverflow(() => visitEveryTab(tester));
        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('keeps every label visible at $c', (tester) async {
        await pumpCase(tester, const OpenRingApp(), c);

        final bar = tester.getRect(find.byType(AppNavigationBar));
        for (final tab in AppTab.values) {
          final label = find.descendant(
            of: find.byKey(AppNavigationBar.destinationKey(tab)),
            matching: find.byType(Text),
          );
          expect(label, findsOneWidget);
          final rect = tester.getRect(label);
          expect(rect.height, greaterThan(0));
          expect(bar.contains(rect.topLeft), isTrue, reason: tab.name);
          expect(rect.bottom, lessThanOrEqualTo(bar.bottom));
        }
      });
    }

    testWidgets('the bar grows with the text scale instead of clipping', (
      tester,
    ) async {
      const base = LayoutCase(
        scale: 1,
        brightness: Brightness.dark,
        locale: Locale('de'),
      );
      await pumpCase(tester, const OpenRingApp(), base);
      final regular = navBarHeight(tester);

      const large = LayoutCase(
        scale: 2,
        brightness: Brightness.dark,
        locale: Locale('de'),
      );
      await pumpCase(tester, const OpenRingApp(), large);

      expect(navBarHeight(tester), greaterThan(regular));
    });
  });
}
