import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';
import 'package:open_ring/features/settings/presentation/notifications_section.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/workout/application/workout_alert_providers.dart';
import 'package:open_ring/features/workout/domain/workout_alert_preferences.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

const _title = 'Alert when the ring drops';
const _detail = 'Vibrates once if the heart rate stops for 30 s';
const _lockTitle = 'Heart rate on the lock screen';

Future<void> _pump(
  WidgetTester tester, {
  required InMemoryWorkoutAlertPreferences preferences,
  NotificationAccess? notifications,
  Locale locale = const Locale('en'),
}) => pumpScaled(
  tester,
  screenHost(const SettingsScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: locale,
  overrides: [
    ...bleOverrides(),
    ...ringOverrides(),
    ...settingsOverrides(notifications: notifications),
    workoutAlertPreferencesProvider.overrideWithValue(preferences),
  ],
);

Finder get _switch => find.byKey(NotificationsSection.ringLostAlertKey);

void main() {
  test('the switch key is settings_ring_lost_alert', () {
    expect(
      NotificationsSection.ringLostAlertKey,
      const Key('settings_ring_lost_alert'),
    );
  });

  group('9: Settings, Notifications, Live workout', () {
    testWidgets('shows the title, the detail and the switch', (tester) async {
      await _pump(tester, preferences: InMemoryWorkoutAlertPreferences());

      await reveal(tester, find.text(_title));

      expect(find.text(_title), findsOneWidget);
      expect(find.text(_detail), findsOneWidget);
      expect(_switch, findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(_title),
            matching: find.byType(SettingsTile),
          ),
          matching: _switch,
        ),
        findsOneWidget,
      );
    });

    testWidgets('sits in the Live workout group', (tester) async {
      await _pump(tester, preferences: InMemoryWorkoutAlertPreferences());

      await reveal(tester, find.text(_title));

      final group = find.ancestor(
        of: find.text(_lockTitle),
        matching: find.byType(TileGroup),
      );
      expect(find.descendant(of: group, matching: find.text(_title)), findsOne);
      expect(
        tester.getTopLeft(find.text(_title)).dy,
        greaterThan(tester.getTopLeft(find.text('Live workout')).dy),
      );
    });

    testWidgets('the switch is on by default', (tester) async {
      await _pump(tester, preferences: InMemoryWorkoutAlertPreferences());

      await reveal(tester, _switch);

      expect(tester.widget<Switch>(_switch).value, isTrue);
      expect(tester.widget<Switch>(_switch).onChanged, isNotNull);
    });

    testWidgets('tapping it stores false', (tester) async {
      final preferences = InMemoryWorkoutAlertPreferences();
      await _pump(tester, preferences: preferences);
      await reveal(tester, _switch);

      await tester.tap(_switch);
      await tester.pumpAndSettle();

      expect(await preferences.alertRingLost(), isFalse);
      expect(tester.widget<Switch>(_switch).value, isFalse);
    });

    testWidgets('a stored false shows the switch off', (tester) async {
      final preferences = InMemoryWorkoutAlertPreferences();
      await preferences.setAlertRingLost(alert: false);
      await _pump(tester, preferences: preferences);

      await reveal(tester, _switch);

      expect(tester.widget<Switch>(_switch).value, isFalse);
    });

    testWidgets('tapping it again stores true', (tester) async {
      final preferences = InMemoryWorkoutAlertPreferences();
      await preferences.setAlertRingLost(alert: false);
      await _pump(tester, preferences: preferences);
      await reveal(tester, _switch);

      await tester.tap(_switch);
      await tester.pumpAndSettle();

      expect(await preferences.alertRingLost(), isTrue);
    });

    testWidgets('with notifications off it is disabled', (tester) async {
      final preferences = InMemoryWorkoutAlertPreferences();
      await _pump(
        tester,
        preferences: preferences,
        notifications: InMemoryNotificationAccess(allowed: false),
      );

      await reveal(tester, _switch);

      expect(tester.widget<Switch>(_switch).onChanged, isNull);
      expect(await preferences.alertRingLost(), isTrue);
    });

    testWidgets('reads in Portuguese', (tester) async {
      await _pump(
        tester,
        preferences: InMemoryWorkoutAlertPreferences(),
        locale: const Locale('pt'),
      );

      await reveal(tester, find.text('Avisar quando o anel cair'));

      expect(find.text('Avisar quando o anel cair'), findsOneWidget);
      expect(find.text('Vibra uma vez se a FC parar por 30 s'), findsOneWidget);
    });
  });
}
