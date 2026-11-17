import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/workout/application/workout_lock_providers.dart';
import 'package:open_ring/features/workout/domain/workout_lock_preferences.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

const _title = 'Heart rate on the lock screen';

Future<void> _pump(
  WidgetTester tester, {
  required InMemoryWorkoutLockPreferences preferences,
  NotificationAccess? notifications,
}) => pumpScaled(
  tester,
  screenHost(const SettingsScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: [
    ...bleOverrides(),
    ...ringOverrides(),
    ...settingsOverrides(notifications: notifications),
    workoutLockPreferencesProvider.overrideWithValue(preferences),
  ],
);

Finder get _switch => find.descendant(
  of: find.ancestor(of: find.text(_title), matching: find.byType(SettingsTile)),
  matching: find.byType(Switch),
);

void main() {
  group('9: Settings, Notifications, Live workout', () {
    testWidgets('shows the sub-header and the switch', (tester) async {
      await _pump(tester, preferences: InMemoryWorkoutLockPreferences());

      await reveal(tester, find.text(_title));

      expect(find.text('Live workout'), findsOneWidget);
      expect(find.text(_title), findsOneWidget);
      expect(_switch, findsOneWidget);
    });

    testWidgets('the switch is on by default', (tester) async {
      await _pump(tester, preferences: InMemoryWorkoutLockPreferences());

      await reveal(tester, find.text(_title));

      expect(tester.widget<Switch>(_switch).value, isTrue);
      expect(tester.widget<Switch>(_switch).onChanged, isNotNull);
    });

    testWidgets('tapping it stores false', (tester) async {
      final preferences = InMemoryWorkoutLockPreferences();
      await _pump(tester, preferences: preferences);
      await reveal(tester, find.text(_title));

      await tester.tap(_switch);
      await tester.pumpAndSettle();

      expect(await preferences.showHeartRate(), isFalse);
      expect(tester.widget<Switch>(_switch).value, isFalse);
    });

    testWidgets('a stored false shows the switch off', (tester) async {
      final preferences = InMemoryWorkoutLockPreferences();
      await preferences.setShowHeartRate(show: false);
      await _pump(tester, preferences: preferences);

      await reveal(tester, find.text(_title));

      expect(tester.widget<Switch>(_switch).value, isFalse);
    });

    testWidgets('tapping it again stores true', (tester) async {
      final preferences = InMemoryWorkoutLockPreferences();
      await preferences.setShowHeartRate(show: false);
      await _pump(tester, preferences: preferences);
      await reveal(tester, find.text(_title));

      await tester.tap(_switch);
      await tester.pumpAndSettle();

      expect(await preferences.showHeartRate(), isTrue);
    });

    testWidgets('with notifications off it is disabled', (tester) async {
      final preferences = InMemoryWorkoutLockPreferences();
      await _pump(
        tester,
        preferences: preferences,
        notifications: InMemoryNotificationAccess(allowed: false),
      );

      await reveal(tester, find.text(_title));

      expect(tester.widget<Switch>(_switch).onChanged, isNull);
      expect(await preferences.showHeartRate(), isTrue);
    });
  });
}
