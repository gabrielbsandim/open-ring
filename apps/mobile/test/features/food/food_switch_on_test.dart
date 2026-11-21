import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../helpers/ble_fakes.dart';
import '../../helpers/layout_harness.dart';
import '../../helpers/onboarding_app.dart';
import '../../helpers/onboarding_fakes.dart';
import '../../helpers/ring_fakes.dart';
import '../../helpers/settings_fakes.dart';
import 'food_fakes.dart';

final _now = DateTime(2026, 11, 21, 15);
final _dashes = RegExp(r'[\u2013\u2014]');

void main() {
  group('Food switch-on copy and privacy across all 11 locales', () {
    test('Goals and Food privacy strings exist with no em or en dashes', () {
      expect(AppLocales.supported, hasLength(11));
      for (final locale in AppLocales.supported) {
        final l = lookupAppLocalizations(locale);
        final tag = locale.toLanguageTag();
        for (final text in [
          l.goalsFormulaLeversFood,
          l.goalsSetupFoodBody,
          l.goalsFormulaCannot2,
          l.privacyStoresFood,
          l.privacyStoresFoodWhy,
          l.privacyDeleteFood,
          l.privacyStoresRingDataWhy,
          l.privacyStoresOtherAppsWhy,
        ]) {
          expect(text.trim(), isNotEmpty, reason: tag);
          expect(_dashes.hasMatch(text), isFalse, reason: '$tag: $text');
        }
      }
    });

    test(
      'Goals English copy and metrics doc no longer say Food awaits a module',
      () {
        final l = lookupAppLocalizations(const Locale('en'));
        expect(
          l.goalsFormulaLeversFood,
          contains('does not include food levers'),
        );
        expect(
          l.goalsFormulaLeversFood,
          contains('only adjusts movement and sleep'),
        );
        expect(
          l.goalsFormulaLeversFood.toLowerCase(),
          isNot(contains('not been built')),
        );
        expect(
          l.goalsFormulaLeversFood.toLowerCase(),
          isNot(contains('wait for')),
        );

        expect(l.goalsSetupFoodBody, contains('does not read your meals'));
        expect(
          l.goalsSetupFoodBody.toLowerCase(),
          isNot(contains('no food module')),
        );
        expect(
          l.goalsSetupFoodBody.toLowerCase(),
          isNot(contains('not been built')),
        );

        expect(l.goalsFormulaCannot2, contains('does not read your meals'));
        expect(
          l.goalsFormulaCannot2,
          contains('only adjusts movement and sleep'),
        );

        final metricsDoc = File('../../docs/metrics.md').readAsStringSync();
        expect(metricsDoc, isNot(contains('wait for a Food module')));
        expect(
          metricsDoc.replaceAll(RegExp(r'\s+'), ' '),
          contains(
            'the plan does not include food levers and only adjusts movement and sleep',
          ),
        );
      },
    );

    test('AndroidManifest declares no camera or photo library permission', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, isNot(contains('android.permission.CAMERA')));
      expect(manifest, isNot(contains('android.permission.READ_MEDIA_IMAGES')));
      expect(
        manifest,
        isNot(contains('android.permission.READ_EXTERNAL_STORAGE')),
      );
    });

    testWidgets('Today reads no Food stores while Food module is off', (
      tester,
    ) async {
      final reads = StoreReads();
      await pumpOnboardingApp(
        tester,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          clockProvider.overrideWithValue(() => _now),
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          ...reads.overrides(),
        ],
      );
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(reads.any, isFalse);
    });

    testWidgets('Modules reads no Food stores while Food module is off', (
      tester,
    ) async {
      final reads = StoreReads();
      await pumpScaled(
        tester,
        screenHost(const ModulesScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...settingsOverrides(),
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          ...reads.overrides(),
        ],
      );
      expect(find.byType(ModulesScreen), findsOneWidget);
      expect(reads.any, isFalse);
    });
  });
}
