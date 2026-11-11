import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/export/presentation/export_screen.dart';
import 'package:open_ring/features/health_sync/presentation/health_status_screen.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';
import 'package:open_ring/features/ring/application/ring_alert_providers.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/domain/app_language.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/settings/presentation/about_section.dart';
import 'package:open_ring/features/settings/presentation/data_sources_screen.dart';
import 'package:open_ring/features/settings/presentation/delete_data_tile.dart';
import 'package:open_ring/features/settings/presentation/language_section.dart';
import 'package:open_ring/features/settings/presentation/notifications_section.dart';
import 'package:open_ring/features/settings/presentation/profile_editor.dart';
import 'package:open_ring/features/settings/presentation/profile_section.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/protocol_lab_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

final _scenarios = <String, List<Override> Function()>{
  'with an empty profile': settingsOverrides,
  'with a full profile in imperial units': () => settingsOverrides(
    profiles: InMemoryUserProfileStore(fullProfile),
    units: InMemoryUnitSystemStore(UnitSystem.imperial),
  ),
  'with notifications off and a chosen language': () => settingsOverrides(
    notifications: InMemoryNotificationAccess(allowed: false),
    languages: InMemoryAppLanguageStore(AppLanguage.japanese),
  ),
};

Future<void> _pump(
  WidgetTester tester, {
  UserProfileStore? profiles,
  UnitSystemStore? units,
  AppLanguageStore? languages,
  NotificationAccess? notifications,
  FakeLocalDataEraser? eraser,
  RecordingExternalLinkOpener? links,
  Widget screen = const SettingsScreen(),
}) => pumpScaled(
  tester,
  screen is OpenRingApp ? screen : screenHost(screen),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: [
    ...protocolLabOverrides(),
    ...ringOverrides(),
    ...settingsOverrides(
      profiles: profiles,
      units: units,
      languages: languages,
      notifications: notifications,
      eraser: eraser,
      links: links,
    ),
  ],
);

Future<void> _openSettingsInApp(WidgetTester tester) async {
  await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(RingScreen.settingsKey));
  await tester.pumpAndSettle();
}

Future<void> _askToDelete(WidgetTester tester) async {
  await reveal(tester, find.byKey(DeleteDataTile.buttonKey));
  await tester.tap(find.byKey(DeleteDataTile.buttonKey));
  await tester.pumpAndSettle();
}

Finder _field(ProfileField field) =>
    find.byKey(ProfileSectionKeys.field(field));

Future<void> _scrollTo(WidgetTester tester, Finder finder) =>
    reveal(tester, finder);

Future<void> _edit(WidgetTester tester, ProfileField field, String text) async {
  await _scrollTo(tester, _field(field));
  await tester.tap(_field(field));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(ProfileEditorKeys.field), text);
  await tester.tap(find.byKey(ProfileEditorKeys.save));
  await tester.pumpAndSettle();
}

String _value(WidgetTester tester, ProfileField field) => tester
    .widgetList<Text>(
      find.descendant(of: _field(field), matching: find.byType(Text)),
    )
    .last
    .data!;

void main() {
  for (final MapEntry(key: name, value: overrides) in _scenarios.entries) {
    group('Settings $name', () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpScaled(
            tester,
            screenHost(const SettingsScreen()),
            textScaler: c.textScaler,
            brightness: c.brightness,
            locale: c.locale,
            overrides: overrides(),
          );

          await scrollThrough(tester);
          expect(find.byType(SettingsScreen), findsOneWidget);
        });
      }
    });
  }

  group('Notification alert toggles', () {
    Future<void> pumpAlerts(
      WidgetTester tester, {
      required InMemoryRingAlertPreferences preferences,
      NotificationAccess? notifications,
    }) => pumpScaled(
      tester,
      screenHost(const SettingsScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: [
        ...protocolLabOverrides(),
        ...ringOverrides(),
        ...settingsOverrides(notifications: notifications),
        ringAlertPreferencesProvider.overrideWithValue(preferences),
      ],
    );

    Switch toggle(WidgetTester tester, RingAlert alert) =>
        tester.widget<Switch>(find.byKey(NotificationsSection.alertKey(alert)));

    testWidgets('both default on with the prototype copy', (tester) async {
      await pumpAlerts(tester, preferences: InMemoryRingAlertPreferences());

      for (final alert in RingAlert.values) {
        await reveal(tester, find.byKey(NotificationsSection.alertKey(alert)));
        expect(toggle(tester, alert).value, isTrue);
      }
      expect(find.text('Alerts when the ring reaches 20%'), findsOneWidget);
      expect(
        find.text('Alerts after 3 attempts without success'),
        findsOneWidget,
      );
    });

    testWidgets('turning one off stores only that one', (tester) async {
      final preferences = InMemoryRingAlertPreferences();
      await pumpAlerts(tester, preferences: preferences);
      final key = NotificationsSection.alertKey(RingAlert.lowBattery);

      await reveal(tester, find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();

      expect(preferences.alerts, {RingAlert.syncFailed});
      expect(toggle(tester, RingAlert.lowBattery).value, isFalse);
    });

    testWidgets('a denied permission shows them off and locked', (
      tester,
    ) async {
      await pumpAlerts(
        tester,
        preferences: InMemoryRingAlertPreferences(),
        notifications: InMemoryNotificationAccess(allowed: false),
      );

      for (final alert in RingAlert.values) {
        await reveal(tester, find.byKey(NotificationsSection.alertKey(alert)));
        expect(toggle(tester, alert).value, isFalse);
        expect(toggle(tester, alert).onChanged, isNull);
      }
    });
  });

  group('Delete confirmation', () {
    for (final c in layoutMatrix()) {
      testWidgets('lays out without overflow at $c', (tester) async {
        await pumpScaled(
          tester,
          screenHost(const SettingsScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: settingsOverrides(),
        );

        await expectNoLayoutOverflow(() => _askToDelete(tester));
        expect(find.byKey(DeleteDataTile.confirmKey), findsOneWidget);
        await expectNoLayoutOverflow(
          () => reveal(tester, find.byKey(DeleteDataTile.confirmKey)),
        );
      });
    }
  });

  testWidgets('About shows the build version and the MIT license', (
    tester,
  ) async {
    await _pump(tester);

    await reveal(tester, find.byKey(AboutSection.licenseKey));

    expect(find.text('Version'), findsOneWidget);
    expect(find.text('1.4.2'), findsOneWidget);
    expect(find.text('License'), findsOneWidget);
    expect(find.text('MIT'), findsOneWidget);
    expect(
      find.textContaining('OpenRing is not a medical device'),
      findsOneWidget,
    );
  });

  testWidgets('the GitHub row opens the repository', (tester) async {
    final links = RecordingExternalLinkOpener();
    await _pump(tester, links: links);

    await reveal(tester, find.byKey(AboutSection.githubKey));
    await tester.tap(find.byKey(AboutSection.githubKey));
    await tester.pumpAndSettle();

    expect(links.opened, [AboutSection.repositoryUrl]);
    expect(
      AboutSection.repositoryUrl.toString(),
      'https://github.com/gabrielbsandim/open-ring',
    );
  });

  testWidgets('following the system names the language in use', (tester) async {
    await _pump(tester);

    await reveal(
      tester,
      find.byKey(LanguageSection.optionKey(AppLanguage.system)),
    );
    expect(find.text('Follow system language'), findsOneWidget);
    expect(find.text('Now: English'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
  });

  testWidgets('choosing a language switches the app and saves it', (
    tester,
  ) async {
    final languages = InMemoryAppLanguageStore();
    await _pump(tester, languages: languages, screen: const OpenRingApp());
    await _openSettingsInApp(tester);

    final german = find.byKey(LanguageSection.optionKey(AppLanguage.german));
    await reveal(tester, german);
    await tester.tap(german);
    await tester.pumpAndSettle();

    expect(languages.language, AppLanguage.german);
    expect(find.text('Sprache'), findsOneWidget);

    final system = find.byKey(LanguageSection.optionKey(AppLanguage.system));
    await reveal(tester, system);
    await tester.tap(system);
    await tester.pumpAndSettle();

    expect(languages.language, AppLanguage.system);
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('allowed notifications show no settings button', (tester) async {
    await _pump(tester);

    await reveal(tester, find.byKey(NotificationsSection.statusKey));
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.byKey(NotificationsSection.openSettingsKey), findsNothing);
  });

  testWidgets('notifications that are off lead to the system settings', (
    tester,
  ) async {
    final access = InMemoryNotificationAccess(allowed: false);
    await _pump(tester, notifications: access);

    await reveal(tester, find.byKey(NotificationsSection.openSettingsKey));
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.byKey(NotificationsSection.openSettingsKey));
    await tester.pumpAndSettle();
    expect(access.settingsOpened, 1);

    access.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Allowed'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation deletes nothing', (tester) async {
    final eraser = FakeLocalDataEraser();
    await _pump(tester, eraser: eraser);

    await _askToDelete(tester);
    expect(find.text('Delete everything on this phone?'), findsOneWidget);
    await tester.tap(find.byKey(DeleteDataTile.cancelKey));
    await tester.pumpAndSettle();

    expect(eraser.erased, 0);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('confirming deletes local data and starts onboarding', (
    tester,
  ) async {
    final eraser = FakeLocalDataEraser();
    await _pump(tester, eraser: eraser, screen: const OpenRingApp());
    await _openSettingsInApp(tester);

    await _askToDelete(tester);
    expect(
      find.textContaining('stays there and can be removed in'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(DeleteDataTile.confirmKey));
    await tester.pumpAndSettle();

    expect(eraser.erased, 1);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('a failed delete stays on Settings and says so', (tester) async {
    await _pump(tester, eraser: FakeLocalDataEraser(fail: true));

    await _askToDelete(tester);
    await tester.tap(find.byKey(DeleteDataTile.confirmKey));
    await tester.pumpAndSettle();

    expect(
      find.text('The data could not be deleted. Try again.'),
      findsOneWidget,
    );
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('shows the stored profile in the chosen units', (tester) async {
    final units = InMemoryUnitSystemStore();
    await _pump(
      tester,
      profiles: InMemoryUserProfileStore(fullProfile),
      units: units,
    );

    expect(_value(tester, ProfileField.age), '34 years');
    expect(_value(tester, ProfileField.sex), 'Female');
    expect(_value(tester, ProfileField.height), '178 cm');
    expect(_value(tester, ProfileField.weight), '76.5 kg');
    expect(_value(tester, ProfileField.maxHeartRate), '186 bpm');
    expect(find.text('Estimated: 220 minus age'), findsOneWidget);
    expect(_value(tester, ProfileField.stepGoal), '12,000 steps');

    await _scrollTo(
      tester,
      find.byKey(SettingsScreen.unitKey(UnitSystem.imperial)),
    );
    await tester.tap(find.byKey(SettingsScreen.unitKey(UnitSystem.imperial)));
    await tester.pumpAndSettle();

    expect(units.units, UnitSystem.imperial);
    await tester.dragUntilVisible(
      _field(ProfileField.height),
      find.byType(Scrollable).first,
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    expect(_value(tester, ProfileField.height), '5 ft 10 in');
    expect(_value(tester, ProfileField.weight), '169 lb');
  });

  testWidgets('editing a field saves the profile', (tester) async {
    final profiles = InMemoryUserProfileStore();
    await _pump(tester, profiles: profiles);

    expect(_value(tester, ProfileField.age), 'Not set');
    await _edit(tester, ProfileField.age, '40');
    expect(profiles.profile?.birthYear, 1986);
    expect(_value(tester, ProfileField.age), '40 years');
    expect(_value(tester, ProfileField.maxHeartRate), '180 bpm');

    await _edit(tester, ProfileField.maxHeartRate, '191');
    expect(profiles.profile?.maxHeartRate, 191);
    expect(profiles.profile?.birthYear, 1986);
    expect(find.text('Your own value'), findsOneWidget);

    await _scrollTo(tester, _field(ProfileField.sex));
    await tester.tap(_field(ProfileField.sex));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProfileEditorKeys.sex(Sex.male)));
    await tester.pumpAndSettle();
    expect(profiles.profile?.sex, Sex.male);
  });

  testWidgets('a value out of range is refused', (tester) async {
    final profiles = InMemoryUserProfileStore();
    await _pump(tester, profiles: profiles);

    await _edit(tester, ProfileField.height, '40');

    expect(find.text('Enter a value from 100 to 230.'), findsOneWidget);
    await tester.tap(find.byKey(ProfileEditorKeys.cancel));
    await tester.pumpAndSettle();
    expect(profiles.profile, isNull);
  });

  testWidgets('imperial height is entered in inches and stored in cm', (
    tester,
  ) async {
    final profiles = InMemoryUserProfileStore();
    await _pump(
      tester,
      profiles: profiles,
      units: InMemoryUnitSystemStore(UnitSystem.imperial),
    );

    await _edit(tester, ProfileField.height, '70');

    expect(profiles.profile?.heightCentimeters, 177.8);
    expect(_value(tester, ProfileField.height), '5 ft 10 in');
  });

  testWidgets('clearing a field removes the value', (tester) async {
    final profiles = InMemoryUserProfileStore(fullProfile);
    await _pump(tester, profiles: profiles);

    await _scrollTo(tester, _field(ProfileField.weight));
    await tester.tap(_field(ProfileField.weight));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProfileEditorKeys.clear));
    await tester.pumpAndSettle();

    expect(profiles.profile?.weightKilograms, isNull);
    expect(profiles.profile?.heightCentimeters, 178);
  });

  for (final (key, screen) in [
    (SettingsScreen.healthKey, HealthStatusScreen),
    (SettingsScreen.exportKey, ExportScreen),
    (SettingsScreen.sourcesKey, DataSourcesScreen),
  ]) {
    testWidgets('the Ring tab reaches $screen through Settings', (
      tester,
    ) async {
      await _pump(tester, screen: const OpenRingApp());
      await _openSettingsInApp(tester);

      await _scrollTo(tester, find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();

      expect(find.byType(screen), findsOneWidget);
    });
  }
}
