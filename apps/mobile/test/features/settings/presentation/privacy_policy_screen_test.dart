import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';
import 'package:open_ring/features/settings/presentation/privacy_policy_screen.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';
import '../../../helpers/workout_fakes.dart';

const _mainActivity =
    'android/app/src/main/kotlin/gbs/openring/app/MainActivity.kt';
const _manifest = 'android/app/src/main/AndroidManifest.xml';
final Uri _privacyLink = Uri.parse('openring://app/privacy');

List<Override> _appOverrides() => [
  ...bleOverrides(),
  ...ringOverrides(),
  ...WorkoutRig().overrides(),
  ringStatusReaderProvider.overrideWithValue(FakeRingStatusReader(freshRing)),
];

Future<void> _pumpApp(WidgetTester tester, {required bool onboarded}) =>
    pumpScaled(
      tester,
      const OpenRingApp(),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      size: const Size(360, 2400),
      onboardingStore: InMemoryOnboardingStore(completed: onboarded),
      overrides: _appOverrides(),
    );

Future<void> _openLink(WidgetTester tester, Uri link) async {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', {
      'location': link.toString(),
      'state': null,
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (_) {},
  );
  await tester.pumpAndSettle();
}

String _normalized(String markdown) =>
    markdown.replaceAll('**', '').replaceAll(RegExp(r'\s+'), ' ');

void main() {
  for (final c in layoutMatrix()) {
    testWidgets('Privacy policy lays out at $c', (tester) async {
      await pumpScaled(
        tester,
        screenHost(const PrivacyPolicyScreen()),
        textScaler: c.textScaler,
        brightness: c.brightness,
        locale: c.locale,
        overrides: settingsOverrides(),
      );

      await scrollThrough(tester);
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    });
  }

  test('every English sentence comes verbatim from the policy document', () {
    final policy = _normalized(
      File('../../docs/privacy-policy.md').readAsStringSync(),
    );
    final l = lookupAppLocalizations(const Locale('en'));

    for (final text in [
      l.privacyTitle,
      l.privacyEffective,
      l.privacyShortHeading,
      l.privacyShortNoAccount,
      l.privacyShortStored,
      l.privacyShortInternet,
      l.privacyShortLeaves,
      l.privacyStoresHeading,
      l.privacyStoresRing,
      l.privacyStoresRingWhy,
      l.privacyStoresRingData,
      l.privacyStoresRingDataWhy,
      l.privacyStoresWorkouts,
      l.privacyStoresWorkoutsWhy,
      l.privacyStoresRatings,
      l.privacyStoresRatingsWhy,
      l.privacyStoresRoutes,
      l.privacyStoresRoutesWhy,
      l.privacyStoresProfile,
      l.privacyStoresProfileWhy,
      l.privacyStoresOtherApps,
      l.privacyStoresOtherAppsWhy,
      l.privacyStoresWeighIns,
      l.privacyStoresWeighInsWhy,
      l.privacyStoresDayTags,
      l.privacyStoresDayTagsWhy,
      l.privacyStoresGoals,
      l.privacyStoresGoalsWhy,
      l.privacyStoresFood,
      l.privacyStoresFoodWhy,
      l.privacyStoresSettings,
      l.privacyStoresSettingsWhy,
      l.privacyStoresSummary,
      l.privacyStoresSummaryWhy,
      l.privacyHealthWrites,
      l.privacyHealthWritesWhy,
      l.privacyHealthReads,
      l.privacyHealthReadsWhy,
      l.privacyHealthShare,
      l.privacyDeleteHeading,
      l.privacyDeleteKept,
      l.privacyDeleteWorkout,
      l.privacyDeleteFood,
      l.privacyDeleteAll,
      l.privacyDeleteHealthConnect,
      l.privacyRevoke,
    ]) {
      expect(policy, contains(text));
    }
  });

  testWidgets('the privacy screen shows the ratings row', (tester) async {
    await pumpScaled(
      tester,
      screenHost(const PrivacyPolicyScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: settingsOverrides(),
    );
    final l = lookupAppLocalizations(const Locale('en'));

    await reveal(tester, find.text(l.privacyStoresRatings));

    expect(find.text(l.privacyStoresRatings), findsOneWidget);
    expect(find.text(l.privacyStoresRatingsWhy), findsOneWidget);
  });

  test('the policy document has the ratings row in the stored table', () {
    final policy = _normalized(
      File('../../docs/privacy-policy.md').readAsStringSync(),
    );
    final l = lookupAppLocalizations(const Locale('en'));
    final row = '| ${l.privacyStoresRatings} |';

    expect(policy, contains(row));
    expect(policy.indexOf(row), lessThan(policy.indexOf('## Permissions')));
    expect(policy, contains(l.privacyStoresRatingsWhy));
  });

  testWidgets('criterion 11: the privacy screen shows the Goals row', (
    tester,
  ) async {
    await pumpScaled(
      tester,
      screenHost(const PrivacyPolicyScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: settingsOverrides(),
    );
    final l = lookupAppLocalizations(const Locale('en'));

    await reveal(tester, find.text(l.privacyStoresGoals));

    expect(find.text(l.privacyStoresGoals), findsOneWidget);
    expect(find.text(l.privacyStoresGoalsWhy), findsOneWidget);
  });

  test('criterion 11: the policy document has the Goals row in the table', () {
    final policy = _normalized(
      File('../../docs/privacy-policy.md').readAsStringSync(),
    );
    final l = lookupAppLocalizations(const Locale('en'));
    final row = '| ${l.privacyStoresGoals} |';

    expect(policy, contains(row));
    expect(policy.indexOf(row), lessThan(policy.indexOf('## Permissions')));
    expect(policy, contains('${l.privacyStoresGoalsWhy} |'));
  });

  test('criterion 11: the Goals row names what the module stores', () {
    final l = lookupAppLocalizations(const Locale('en'));
    final row = '${l.privacyStoresGoals} ${l.privacyStoresGoalsWhy}'
        .toLowerCase();

    for (final word in [
      'start',
      'reference',
      'check-in',
      'pregnan',
      'screening',
    ]) {
      expect(row, contains(word), reason: word);
    }
  });

  testWidgets('criterion 10: the privacy screen names Effort in five rows', (
    tester,
  ) async {
    await pumpScaled(
      tester,
      screenHost(const PrivacyPolicyScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: settingsOverrides(),
    );
    final l = lookupAppLocalizations(const Locale('en'));
    final whys = {
      'ring data': l.privacyStoresRingDataWhy,
      'workouts': l.privacyStoresWorkoutsWhy,
      'profile': l.privacyStoresProfileWhy,
      'other apps': l.privacyStoresOtherAppsWhy,
      'day tags': l.privacyStoresDayTagsWhy,
    };

    for (final MapEntry(key: row, value: why) in whys.entries) {
      expect(why, contains('Effort'), reason: row);
      await reveal(tester, find.text(why));
      expect(find.text(why), findsOneWidget, reason: row);
    }
  });

  test('criterion 10: the policy document names Effort in the five rows', () {
    final policy = _normalized(
      File('../../docs/privacy-policy.md').readAsStringSync(),
    );
    final l = lookupAppLocalizations(const Locale('en'));

    for (final why in [
      l.privacyStoresRingDataWhy,
      l.privacyStoresWorkoutsWhy,
      l.privacyStoresProfileWhy,
      l.privacyStoresOtherAppsWhy,
      l.privacyStoresDayTagsWhy,
    ]) {
      expect(why, contains('Effort'));
      expect(policy, contains(why));
    }
    expect(l.privacyStoresDayTagsWhy, contains('Open Score and Effort'));
  });

  testWidgets('the Health Connect link opens the privacy screen', (
    tester,
  ) async {
    await _pumpApp(tester, onboarded: true);

    await _openLink(tester, _privacyLink);

    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
  });

  testWidgets('the link works while onboarding asks for permissions', (
    tester,
  ) async {
    await _pumpApp(tester, onboarded: false);
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await _openLink(tester, _privacyLink);

    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
  });

  testWidgets('with nothing to go back to, close leaves for Today', (
    tester,
  ) async {
    await _pumpApp(tester, onboarded: true);
    await _openLink(tester, _privacyLink);

    await tester.tap(find.byKey(PrivacyPolicyScreen.closeKey));
    await tester.pumpAndSettle();

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(PrivacyPolicyScreen), findsNothing);
  });

  testWidgets('close during onboarding returns to onboarding', (tester) async {
    await _pumpApp(tester, onboarded: false);
    await _openLink(tester, _privacyLink);

    await tester.tap(find.byKey(PrivacyPolicyScreen.closeKey));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('the full policy opens the public document', (tester) async {
    final links = RecordingExternalLinkOpener();
    await pumpScaled(
      tester,
      screenHost(const PrivacyPolicyScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: settingsOverrides(links: links),
    );

    await reveal(tester, find.byKey(PrivacyPolicyScreen.fullPolicyKey));
    await tester.tap(find.byKey(PrivacyPolicyScreen.fullPolicyKey));
    await tester.pumpAndSettle();

    expect(links.opened, [PrivacyPolicyScreen.fullPolicyUrl]);
  });

  test('the redirect only exempts the privacy route', () {
    expect(
      onboardingRedirect(completed: false, location: AppPaths.privacy),
      isNull,
    );
    expect(
      onboardingRedirect(completed: false, location: AppTab.today.path),
      isNotNull,
    );
  });

  test('MainActivity routes both Health Connect actions to the screen', () {
    final kotlin = File(_mainActivity).readAsStringSync();

    expect(
      kotlin,
      contains('androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE'),
    );
    expect(kotlin, contains('Intent.ACTION_VIEW_PERMISSION_USAGE'));
    expect(kotlin, contains('"$_privacyLink"'));
    expect(
      File(_manifest).readAsStringSync(),
      contains('androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE'),
    );
  });

  testWidgets('the privacy screen shows the Meals row and Food delete line', (
    tester,
  ) async {
    await pumpScaled(
      tester,
      screenHost(const PrivacyPolicyScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: settingsOverrides(),
    );
    final l = lookupAppLocalizations(const Locale('en'));

    await reveal(tester, find.text(l.privacyStoresFood));
    expect(find.text(l.privacyStoresFood), findsOneWidget);
    expect(find.text(l.privacyStoresFoodWhy), findsOneWidget);

    await reveal(tester, find.text(l.privacyDeleteFood));
    expect(find.text(l.privacyDeleteFood), findsOneWidget);
  });

  test('the policy document describes Food storage, deletions, and no camera '
      'permission', () {
    final policy = _normalized(
      File('../../docs/privacy-policy.md').readAsStringSync(),
    );
    final l = lookupAppLocalizations(const Locale('en'));
    final row = '| ${l.privacyStoresFood} |';

    expect(policy, contains(row));
    expect(policy.indexOf(row), lessThan(policy.indexOf('## Permissions')));
    expect(policy, contains('${l.privacyStoresFoodWhy} |'));
    for (final why in [
      l.privacyStoresRingDataWhy,
      l.privacyStoresOtherAppsWhy,
    ]) {
      expect(why, contains('Food'));
      expect(why, contains('meal comparisons'));
      expect(policy, contains(why));
    }
    expect(policy, contains('- ${l.privacyDeleteFood}'));
    expect(policy, contains('No camera or photo library permission is asked'));
    expect(policy, contains('up to 20 at once'));
    final manifest = File(_manifest).readAsStringSync();
    expect(manifest, isNot(contains('android.permission.CAMERA')));
    expect(manifest, isNot(contains('android.permission.READ_MEDIA_IMAGES')));
  });
}
