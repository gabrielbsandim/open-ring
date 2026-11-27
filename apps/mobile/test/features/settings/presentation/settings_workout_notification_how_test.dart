import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';
import 'package:open_ring/features/settings/presentation/notifications_section.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/workout/presentation/workout_notification_how_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

const _tile = 'How it works';
const _detail = 'What the notification shows and when it updates';
const _ringLostTitle = 'Alert when the ring drops';

Future<void> _pump(
  WidgetTester tester, {
  Widget screen = const SettingsScreen(),
  NotificationAccess? notifications,
  Locale locale = const Locale('en'),
}) => pumpScaled(
  tester,
  screen is OpenRingApp ? screen : screenHost(screen),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: locale,
  overrides: [
    ...bleOverrides(),
    ...ringOverrides(),
    ...settingsOverrides(notifications: notifications),
  ],
);

Future<void> _openSettingsInApp(WidgetTester tester) async {
  await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(RingScreen.settingsKey));
  await tester.pumpAndSettle();
}

Finder get _how => find.byKey(NotificationsSection.howKey);

void main() {
  test('the key is settings_workout_notification_how', () {
    expect(
      NotificationsSection.howKey,
      const Key('settings_workout_notification_how'),
    );
  });

  test('the path sits under Settings', () {
    expect(
      AppPaths.settingsWorkoutNotification,
      '/ring/settings/workout-notification',
    );
  });

  group('1: Settings, Live workout, How it works', () {
    testWidgets('shows the title, the detail and a chevron', (tester) async {
      await _pump(tester);

      await reveal(tester, _how);

      expect(
        find.descendant(of: _how, matching: find.text(_tile)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _how, matching: find.text(_detail)),
        findsOneWidget,
      );
      expect(tester.widget<SettingsTile>(_how).chevron, isTrue);
    });

    testWidgets('is the third tile of the Live workout group', (tester) async {
      await _pump(tester);

      await reveal(tester, _how);

      final group = find.ancestor(
        of: find.text(_ringLostTitle),
        matching: find.byType(TileGroup),
      );
      expect(find.descendant(of: group, matching: _how), findsOneWidget);
      final tiles = tester
          .widgetList<SettingsTile>(
            find.descendant(of: group, matching: find.byType(SettingsTile)),
          )
          .toList();
      expect(tiles, hasLength(3));
      expect(tiles.last.key, NotificationsSection.howKey);
    });

    testWidgets('is enabled with notifications on', (tester) async {
      await _pump(tester);

      await reveal(tester, _how);

      expect(tester.widget<SettingsTile>(_how).onTap, isNotNull);
    });

    testWidgets('stays enabled with notifications off', (tester) async {
      await _pump(
        tester,
        notifications: InMemoryNotificationAccess(allowed: false),
      );

      await reveal(tester, _how);

      expect(tester.widget<SettingsTile>(_how).onTap, isNotNull);
    });

    testWidgets('reads in Portuguese', (tester) async {
      await _pump(tester, locale: const Locale('pt'));

      await reveal(tester, _how);

      expect(find.text('Como funciona'), findsOneWidget);
      expect(
        find.text('O que a notificação mostra e quando atualiza'),
        findsOneWidget,
      );
    });
  });

  group('2: the tile opens the screen inside the app router', () {
    for (final (name, notifications) in [
      ('on', null),
      ('off', InMemoryNotificationAccess(allowed: false)),
    ]) {
      testWidgets('with notifications $name', (tester) async {
        await _pump(
          tester,
          screen: const OpenRingApp(),
          notifications: notifications,
        );
        await _openSettingsInApp(tester);

        await reveal(tester, _how);
        await tester.tap(_how);
        await tester.pumpAndSettle();

        expect(find.byType(WorkoutNotificationHowScreen), findsOneWidget);
      });
    }

    testWidgets('back returns to Settings', (tester) async {
      await _pump(tester, screen: const OpenRingApp());
      await _openSettingsInApp(tester);
      await reveal(tester, _how);
      await tester.tap(_how);
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutNotificationHowScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}
