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
      l.privacyStoresRoutes,
      l.privacyStoresRoutesWhy,
      l.privacyStoresProfile,
      l.privacyStoresProfileWhy,
      l.privacyStoresOtherApps,
      l.privacyStoresOtherAppsWhy,
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
      l.privacyDeleteAll,
      l.privacyDeleteHealthConnect,
      l.privacyRevoke,
    ]) {
      expect(policy, contains(text));
    }
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
}
