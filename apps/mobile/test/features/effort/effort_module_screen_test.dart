import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/effort/presentation/effort_module_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../helpers/ble_fakes.dart';
import '../../helpers/layout_harness.dart';
import '../../helpers/ring_fakes.dart';
import '../../helpers/settings_fakes.dart';
import '../../helpers/workout_fakes.dart';
import '../../helpers/workout_rating_fakes.dart';
import '../workout/presentation/workout_scenarios.dart';

SavedWorkout _saved({int? rating}) {
  final run = savedRun();
  return SavedWorkout(
    id: run.id,
    workout: run.workout,
    utcOffset: run.utcOffset,
    health: run.health,
    rating: rating,
  );
}

ImportedWorkout _imported({int? rating}) => ImportedWorkout(
  recordId: 'ride',
  source: 'com.garmin.android.apps.connectmobile',
  type: WorkoutType.cycling,
  start: workoutStart,
  end: workoutStart.add(const Duration(minutes: 45)),
  utcOffset: Duration.zero,
  rating: rating,
);

MemoryRatings _rated() =>
    MemoryRatings(saved: [_saved(rating: 7)], imported: [_imported(rating: 4)]);

MemoryRatings _unrated() =>
    MemoryRatings(saved: [_saved()], imported: [_imported()]);

GoRouter _router() => GoRouter(
  initialLocation: AppPaths.settingsModuleEffort,
  routes: [
    GoRoute(
      path: AppPaths.settingsModuleEffort,
      builder: (_, _) => const EffortModuleScreen(),
    ),
    GoRoute(
      path: AppPaths.effortFormula,
      builder: (_, _) => const Scaffold(body: Text('formula screen')),
    ),
  ],
);

List<Override> _overrides(MemoryRatings memory, InMemoryModuleStore modules) =>
    [
      ...bleOverrides(),
      ...ringOverrides(),
      moduleStoreProvider.overrideWithValue(modules),
      workoutHistoryReaderProvider.overrideWithValue(memory),
      importedWorkoutReaderProvider.overrideWithValue(ImportedRatings(memory)),
      workoutRatingStoreProvider.overrideWithValue(memory),
    ];

Future<void> _pump(
  WidgetTester tester,
  MemoryRatings memory, {
  InMemoryModuleStore? modules,
  Locale locale = const Locale('en'),
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  final router = _router();
  addTearDown(router.dispose);
  await pumpScaled(
    tester,
    MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localeListResolutionCallback: AppLocales.resolve,
      supportedLocales: AppLocales.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    ),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    overrides: _overrides(memory, modules ?? InMemoryModuleStore()),
  );
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

int _revision(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(EffortModuleScreen)))
        .read(dataRevisionProvider);

Finder _inState(String text) => find.descendant(
  of: find.byKey(EffortModuleKeys.state),
  matching: find.text(text),
);

void main() {
  group('criterion 3: the module screen and its pill', () {
    testWidgets('shows the title, the detail and the Off pill', (tester) async {
      await _pump(tester, _unrated());

      expect(find.byType(EffortModuleScreen), findsOneWidget);
      expect(find.text('Effort'), findsWidgets);
      expect(
        find.text(
          'How much you trained this week and whether today is a day to '
          'push, maintain or recover.',
        ),
        findsOneWidget,
      );
      expect(_inState('Off'), findsOneWidget);
      expect(_inState('On'), findsNothing);
    });

    testWidgets('shows the On pill when the module is on', (tester) async {
      await _pump(
        tester,
        _unrated(),
        modules: InMemoryModuleStore({ModuleId.effort}),
      );

      expect(_inState('On'), findsOneWidget);
      expect(_inState('Off'), findsNothing);
    });

    testWidgets('the formula link opens the formula screen', (tester) async {
      await _pump(tester, _unrated());
      await _tap(tester, EffortModuleKeys.formula);

      expect(find.text('formula screen'), findsOneWidget);
    });

    testWidgets('the toggle turns the module on and off, keeping ratings', (
      tester,
    ) async {
      final memory = _rated();
      final modules = InMemoryModuleStore();
      await _pump(tester, memory, modules: modules);
      await reveal(tester, find.byKey(EffortModuleKeys.toggle));

      expect(find.text('Turn Effort on'), findsOneWidget);
      await _tap(tester, EffortModuleKeys.toggle);

      expect(await modules.read(), {ModuleId.effort});
      expect(find.text('Turn Effort off'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(_inState('On'), findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tester.pumpAndSettle();
      await _tap(tester, EffortModuleKeys.toggle);

      expect(await modules.read(), isEmpty);
      await reveal(tester, find.byKey(EffortModuleKeys.toggle));
      expect(find.text('Turn Effort on'), findsOneWidget);
      expect(memory.ratedCount, 2);
      expect(memory.clearCalls, 0);
    });
  });

  group('criterion 8: no rating stored', () {
    testWidgets('the delete action is absent and the empty text shows', (
      tester,
    ) async {
      await _pump(
        tester,
        _unrated(),
        modules: InMemoryModuleStore({ModuleId.effort}),
      );

      expect(find.byKey(EffortModuleKeys.delete), findsNothing);
      expect(find.byKey(EffortModuleKeys.kept), findsNothing);
      await reveal(tester, find.byKey(EffortModuleKeys.stored));
      expect(
        find.text('No effort ratings stored on this phone.'),
        findsOneWidget,
      );
    });

    testWidgets('with the module off the delete action is absent too', (
      tester,
    ) async {
      await _pump(tester, _unrated());

      expect(find.byKey(EffortModuleKeys.delete), findsNothing);
      expect(find.byKey(EffortModuleKeys.kept), findsNothing);
    });
  });

  group('criterion 7: the module off keeps ratings and the delete action', () {
    testWidgets('says the ratings are kept and still offers the delete', (
      tester,
    ) async {
      await _pump(tester, _rated());

      expect(find.byKey(EffortModuleKeys.kept), findsOneWidget);
      expect(
        find.text(
          'Effort is off. Ratings kept on this phone: 2. They count again '
          'when you turn it on.',
        ),
        findsOneWidget,
      );
      await reveal(tester, find.byKey(EffortModuleKeys.delete));
      expect(find.text('Delete effort ratings'), findsOneWidget);
      expect(find.byKey(EffortModuleKeys.delete), findsOneWidget);
    });

    testWidgets('with the module on there is no kept notice', (tester) async {
      await _pump(
        tester,
        _rated(),
        modules: InMemoryModuleStore({ModuleId.effort}),
      );

      expect(find.byKey(EffortModuleKeys.kept), findsNothing);
      await reveal(tester, find.byKey(EffortModuleKeys.stored));
      expect(
        find.text('Workouts with an effort rating on this phone: 2.'),
        findsOneWidget,
      );
      expect(find.byKey(EffortModuleKeys.delete), findsOneWidget);
    });

    testWidgets('deleting with the module off clears and keeps it off', (
      tester,
    ) async {
      final memory = _rated();
      final modules = InMemoryModuleStore();
      await _pump(tester, memory, modules: modules);
      await _tap(tester, EffortModuleKeys.delete);
      await tester.tap(find.byKey(EffortModuleKeys.deleteConfirm));
      await tester.pumpAndSettle();

      expect(memory.ratedCount, 0);
      expect(await modules.read(), isEmpty);
      expect(find.byKey(EffortModuleKeys.kept), findsNothing);
      expect(find.byKey(EffortModuleKeys.delete), findsNothing);
    });
  });

  group('criterion 5: confirming and cancelling the dialog', () {
    testWidgets('the dialog names the count and the consequence', (
      tester,
    ) async {
      await _pump(
        tester,
        _rated(),
        modules: InMemoryModuleStore({ModuleId.effort}),
      );
      await _tap(tester, EffortModuleKeys.delete);

      expect(find.text('Delete the effort ratings?'), findsOneWidget);
      expect(
        find.text(
          'Ratings to delete: 2. The workouts stay. This cannot be undone. '
          'Their load goes back to heart rate or the default of the type.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling writes nothing', (tester) async {
      final memory = _rated();
      await _pump(
        tester,
        memory,
        modules: InMemoryModuleStore({ModuleId.effort}),
      );
      await _tap(tester, EffortModuleKeys.delete);
      final before = _revision(tester);
      await tester.tap(find.byKey(EffortModuleKeys.deleteCancel));
      await tester.pumpAndSettle();

      expect(memory.clearCalls, 0);
      expect(memory.ratedCount, 2);
      expect(_revision(tester), before);
      expect(find.text('Effort ratings deleted.'), findsNothing);
      expect(find.byKey(EffortModuleKeys.delete), findsOneWidget);
    });

    testWidgets('confirming clears, says so, bumps once and leaves it on', (
      tester,
    ) async {
      final memory = _rated();
      final modules = InMemoryModuleStore({ModuleId.effort});
      await _pump(tester, memory, modules: modules);
      await _tap(tester, EffortModuleKeys.delete);
      final before = _revision(tester);
      await tester.tap(find.byKey(EffortModuleKeys.deleteConfirm));
      await tester.pumpAndSettle();

      expect(memory.clearCalls, 1);
      expect(memory.ratingOfSaved(savedRunId), isNull);
      expect(memory.ratingOfImported('ride'), isNull);
      expect(await memory.byId(savedRunId), isNotNull);
      expect(await memory.importedById('ride'), isNotNull);
      expect(_revision(tester), before + 1);
      expect(await modules.read(), {ModuleId.effort});
      expect(find.text('Effort ratings deleted.'), findsOneWidget);
      expect(
        find.text('No effort ratings stored on this phone.'),
        findsOneWidget,
      );
      expect(find.byKey(EffortModuleKeys.delete), findsNothing);
    });
  });

  group('criterion 6: a store that throws', () {
    testWidgets('says the delete failed and clears nothing', (tester) async {
      final memory = _rated()..failure = StateError('disk');
      await _pump(
        tester,
        memory,
        modules: InMemoryModuleStore({ModuleId.effort}),
      );
      await _tap(tester, EffortModuleKeys.delete);
      final before = _revision(tester);
      await tester.tap(find.byKey(EffortModuleKeys.deleteConfirm));
      await tester.pumpAndSettle();

      expect(memory.clearCalls, 1);
      expect(
        find.text('The effort ratings could not be deleted. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Effort ratings deleted.'), findsNothing);
      expect(memory.ratedCount, 2);
      expect(_revision(tester), before);
      expect(find.byKey(EffortModuleKeys.delete), findsOneWidget);
    });
  });

  group('criterion 9: every locale carries the new keys', () {
    for (final locale in AppLocales.supported) {
      test('moduleEffort strings in $locale', () {
        final l = lookupAppLocalizations(locale);
        final en = lookupAppLocalizations(const Locale('en'));
        final texts = [
          l.moduleEffortDetail,
          l.moduleEffortTurnedOn('x'),
          l.moduleEffortKept(3),
          l.moduleEffortDataTitle,
          l.moduleEffortDataEmpty,
          l.moduleEffortDataCount(3),
          l.moduleEffortDelete,
          l.moduleEffortDeleteTitle,
          l.moduleEffortDeleteBody(3),
          l.moduleEffortDeleted,
          l.moduleEffortDeleteFailed,
          l.moduleEffortTurnOn,
          l.moduleEffortTurnOff,
        ];

        for (final text in texts) {
          expect(text.trim(), isNotEmpty);
        }
        expect(l.moduleEffortKept(3), contains('3'));
        expect(l.moduleEffortDataCount(3), contains('3'));
        expect(l.moduleEffortDeleteBody(3), contains('3'));
        expect(l.moduleEffortTurnedOn('TODAYX'), contains('TODAYX'));
        if (locale.languageCode == 'en') return;
        expect(l.moduleEffortDetail, isNot(en.moduleEffortDetail));
        expect(
          l.moduleEffortDeleteBody(3),
          isNot(en.moduleEffortDeleteBody(3)),
        );
      });
    }

    test('ru has distinct plural forms of the delete body', () {
      final l = lookupAppLocalizations(const Locale('ru'));
      final forms = {
        for (final n in [1, 2, 5])
          l.moduleEffortDeleteBody(n).replaceAll('$n', '#'),
      };

      expect(forms, hasLength(3));
      for (final n in [1, 2, 5, 21, 22, 25]) {
        expect(l.moduleEffortDeleteBody(n), contains('$n'));
        expect(l.moduleEffortKept(n), contains('$n'));
        expect(l.moduleEffortDataCount(n), contains('$n'));
      }
    });

    test('ja carries the count in every plural message', () {
      final l = lookupAppLocalizations(const Locale('ja'));

      for (final n in [0, 1, 2, 5]) {
        expect(l.moduleEffortDeleteBody(n), contains('$n'));
        expect(l.moduleEffortKept(n), contains('$n'));
        expect(l.moduleEffortDataCount(n), contains('$n'));
      }
    });
  });

  group('criterion 9: layout', () {
    for (final locale in AppLocales.supported) {
      for (final scale in layoutScales) {
        for (final brightness in Brightness.values) {
          final name = '$locale ${scale}x ${brightness.name}';

          testWidgets('fits with ratings, module off: $name', (tester) async {
            await _pump(
              tester,
              _rated(),
              locale: locale,
              scale: scale,
              brightness: brightness,
            );
            await scrollThrough(tester);

            expect(find.byType(EffortModuleScreen), findsOneWidget);
          });

          testWidgets('fits with ratings, module on, dialog: $name', (
            tester,
          ) async {
            await _pump(
              tester,
              _rated(),
              modules: InMemoryModuleStore({ModuleId.effort}),
              locale: locale,
              scale: scale,
              brightness: brightness,
            );
            await scrollThrough(tester);
            await reveal(tester, find.byKey(EffortModuleKeys.delete));
            await expectNoLayoutOverflow(() async {
              await tester.tap(find.byKey(EffortModuleKeys.delete));
              await tester.pumpAndSettle();
            });

            expect(find.byKey(EffortModuleKeys.deleteConfirm), findsOneWidget);
          });

          testWidgets('fits empty: $name', (tester) async {
            await _pump(
              tester,
              _unrated(),
              locale: locale,
              scale: scale,
              brightness: brightness,
            );
            await scrollThrough(tester);

            expect(find.byType(EffortModuleScreen), findsOneWidget);
          });
        }
      }
    }
  });
}
