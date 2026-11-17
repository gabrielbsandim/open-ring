import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/goals/application/goal_intake_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/application/goals_data.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/infrastructure/drift_goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/settings/infrastructure/drift_user_profile_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/database.dart';
import '../goal_fixtures.dart';
import '../goals_data_harness.dart';

final _emDash = String.fromCharCode(0x2014);
final _enDash = String.fromCharCode(0x2013);

AppLocalizations _en() => lookupAppLocalizations(const Locale('en'));

Future<({GoalSetup setup, InMemoryGoalStore memory, SpyGoalStore spy})> _world({
  Set<ModuleId> modules = goalModules,
  bool seed = true,
}) async {
  final memory = InMemoryGoalStore();
  final spy = SpyGoalStore(memory);
  if (seed) await seedGoalsData(memory);
  final setup = await setupGoals(
    modules: modules,
    store: memory,
    readStore: spy,
  );
  return (setup: setup, memory: memory, spy: spy);
}

void main() {
  group('GoalsDataCount', () {
    test('total adds goals, reviews and screenings', () {
      const count = GoalsDataCount(goals: 1, reviews: 3, screenings: 2);

      expect(count.total, 6);
    });

    test('total is zero for an empty count', () {
      const count = GoalsDataCount(goals: 0, reviews: 0, screenings: 0);

      expect(count.total, 0);
    });
  });

  group('7. goalsDataCountProvider', () {
    test('counts goals, weeks of every goal and screenings', () async {
      final world = await _world();
      await world.memory.end(
        1,
        on: goalDay(12, 8),
        reason: GoalEndReason.person,
      );
      await world.memory.start(goalDraft());
      await world.memory.addWeek(
        2,
        monday: goalDay(12, 14),
        inputs: f1,
        review: reviewWeek(f1),
      );

      final count = await world.setup.container.read(
        goalsDataCountProvider.future,
      );

      expect(count.goals, 2);
      expect(count.reviews, 4);
      expect(count.screenings, 1);
      expect(count.total, 7);
    });

    test('is zero with nothing stored', () async {
      final world = await _world(seed: false);

      final count = await world.setup.container.read(
        goalsDataCountProvider.future,
      );

      expect(count.total, 0);
    });

    test('is not gated on the module being on', () async {
      final world = await _world(modules: const {});

      final count = await world.setup.container.read(
        goalsDataCountProvider.future,
      );

      expect(count.goals, 1);
      expect(count.reviews, 3);
      expect(count.screenings, 1);
    });

    test('reads again after the data revision moves', () async {
      final world = await _world(seed: false);
      final container = world.setup.container;
      expect((await container.read(goalsDataCountProvider.future)).total, 0);

      await seedGoalsData(world.memory);
      container.read(dataRevisionProvider.notifier).bump();

      expect((await container.read(goalsDataCountProvider.future)).total, 5);
    });

    test('screenings alone count and report no goal', () async {
      final world = await _world(seed: false);
      await seedGoalsData(world.memory, goal: false, screenings: 2);

      final count = await world.setup.container.read(
        goalsDataCountProvider.future,
      );

      expect(count.goals, 0);
      expect(count.reviews, 0);
      expect(count.screenings, 2);
    });
  });

  group('7. goalsDataEraserProvider confirm', () {
    test('clear empties the three stores and answers true', () async {
      final world = await _world();
      final container = world.setup.container;

      final cleared = await container.read(goalsDataEraserProvider).clear();

      expect(cleared, isTrue);
      expect(world.spy.clearCalls, 1);
      expect(await world.memory.goals(), isEmpty);
      expect(await world.memory.weeks(1), isEmpty);
      expect(await world.memory.screenings(), isEmpty);
      expect(await world.memory.count(), 0);
    });

    test('the revision moves once and the readers see nothing', () async {
      final world = await _world();
      final container = world.setup.container;
      expect(await container.read(softModeProvider.future), isTrue);
      expect(await container.read(activeGoalProvider.future), isNotNull);
      final before = world.setup.revision;

      await container.read(goalsDataEraserProvider).clear();

      expect(world.setup.revision, before + 1);
      expect(await container.read(softModeProvider.future), isNull);
      expect(await container.read(activeGoalProvider.future), isNull);
      expect(
        await container.read(goalWeekProvider.future),
        isA<GoalWeekNoGoal>(),
      );
      expect((await container.read(goalsDataCountProvider.future)).total, 0);
    });

    test('clearing an empty store still answers true', () async {
      final world = await _world(seed: false);

      expect(
        await world.setup.container.read(goalsDataEraserProvider).clear(),
        isTrue,
      );
    });

    test('does not switch Goals on or off', () async {
      final world = await _world();
      final container = world.setup.container;

      await container.read(goalsDataEraserProvider).clear();

      expect(await container.read(enabledModulesProvider.future), goalModules);
    });

    test('works with Goals off and leaves it off', () async {
      final world = await _world(modules: const {ModuleId.body});
      final container = world.setup.container;

      final cleared = await container.read(goalsDataEraserProvider).clear();

      expect(cleared, isTrue);
      expect(await world.memory.count(), 0);
      expect(await container.read(enabledModulesProvider.future), {
        ModuleId.body,
      });
    });
  });

  group('9. goalsDataEraserProvider with a store that throws', () {
    test('answers false, logs it and keeps every row', () async {
      final world = await _world();
      world.spy.clearFailure = StateError('disk');
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = original);

      final cleared = await world.setup.container
          .read(goalsDataEraserProvider)
          .clear();

      expect(cleared, isFalse);
      expect(world.spy.clearCalls, 1);
      expect(logs, isNotEmpty);
      expect(logs.join('\n'), contains('disk'));
      expect(await world.memory.count(), 5);
    });

    test('the readers still see the rows', () async {
      final world = await _world();
      world.spy.clearFailure = StateError('disk');
      final container = world.setup.container;

      await container.read(goalsDataEraserProvider).clear();

      expect((await container.read(goalsDataCountProvider.future)).total, 5);
      expect(await container.read(softModeProvider.future), isTrue);
    });
  });

  group('7. the eraser touches the Goals tables only', () {
    test('weigh-ins, step goal changes and the profile step goal stay', () async {
      final db = memoryDatabase();
      final goalStore = DriftGoalStore(db);
      await goalStore.start(goalDraft());
      await goalStore.addWeek(
        1,
        monday: goalDay(12, 7),
        inputs: f1,
        review: reviewWeek(f1),
      );
      await goalStore.addScreening(
        GoalScreening(
          on: goalDay(12, 1),
          softMode: true,
          pregnantOrBreastfeeding: null,
        ),
      );
      await db.customStatement(
        'INSERT INTO weigh_ins (at_utc_ms, offset_minutes, kilograms, source) '
        "VALUES (1, 0, 78.2, 'manual')",
      );
      await db.customStatement(
        'INSERT INTO step_goal_changes (effective_date, steps) '
        "VALUES ('1970-01-01', 8000), ('2026-12-07', 10000)",
      );
      final profiles = DriftUserProfileStore(db);
      await profiles.save(
        const UserProfile(birthYear: 1990, dailyStepGoal: 10000),
        at: DateTime(2026, 12, 7),
      );
      final container = ProviderContainer.test(
        overrides: [
          goalStoreProvider.overrideWithValue(goalStore),
          moduleStoreProvider.overrideWithValue(
            InMemoryModuleStore(goalModules),
          ),
        ],
      );

      final cleared = await container.read(goalsDataEraserProvider).clear();

      expect(cleared, isTrue);
      expect(await rowCount(db, 'goals'), 0);
      expect(await rowCount(db, 'goal_weeks'), 0);
      expect(await rowCount(db, 'goal_screenings'), 0);
      expect(await rowCount(db, 'weigh_ins'), 1);
      expect(await rowCount(db, 'step_goal_changes'), 2);
      expect((await profiles.read())?.dailyStepGoal, 10000);
      expect((await profiles.read())?.birthYear, 1990);
    });
  });

  group('6. goalsDataLine', () {
    test('0 rows gives the empty line', () {
      final l10n = _en();

      expect(
        goalsDataLine(
          l10n,
          const GoalsDataCount(goals: 0, reviews: 0, screenings: 0),
        ),
        l10n.moduleGoalsDataEmpty,
      );
    });

    test(
      '1 goal, 3 reviews and 1 screening gives the counts and the sentence',
      () {
        final l10n = _en();

        final line = goalsDataLine(
          l10n,
          const GoalsDataCount(goals: 1, reviews: 3, screenings: 1),
        );

        expect(line, contains(l10n.moduleGoalsDataCount(1, 3)));
        expect(line, contains(l10n.moduleGoalsDataScreening));
        expect(line, isNot(contains(l10n.moduleGoalsDataEmpty)));
      },
    );

    test('screenings alone give the screening sentence alone', () {
      final l10n = _en();

      final line = goalsDataLine(
        l10n,
        const GoalsDataCount(goals: 0, reviews: 0, screenings: 2),
      );

      expect(line, l10n.moduleGoalsDataScreening);
    });

    test('a goal with no screening has no screening sentence', () {
      final l10n = _en();

      final line = goalsDataLine(
        l10n,
        const GoalsDataCount(goals: 1, reviews: 0, screenings: 0),
      );

      expect(line, l10n.moduleGoalsDataCount(1, 0));
      expect(line, isNot(contains(l10n.moduleGoalsDataScreening)));
    });

    for (final locale in AppLocales.supported) {
      test('$locale fills every placeholder for 0, 1, 2, 5 and 21', () {
        final l10n = lookupAppLocalizations(locale);

        for (final (goals, reviews) in [
          (1, 0),
          (1, 1),
          (2, 2),
          (5, 0),
          (21, 5),
        ]) {
          final text = l10n.moduleGoalsDataCount(goals, reviews);

          expect(text, contains('$goals'), reason: '$goals $reviews');
          expect(text, isNot(contains('{')), reason: '$goals $reviews');
          expect(text, isNot(contains('plural')), reason: '$goals $reviews');
        }
      });

      test('$locale spells the reviews count', () {
        final l10n = lookupAppLocalizations(locale);

        for (final reviews in [3, 7, 21]) {
          expect(
            l10n.moduleGoalsDataCount(1, reviews),
            contains('$reviews'),
            reason: '$reviews',
          );
        }
      });
    }

    test('English says no reviews at zero', () {
      expect(_en().moduleGoalsDataCount(1, 0), contains('no reviews'));
    });

    test('Russian reviews take the one, few and many forms', () {
      final l10n = lookupAppLocalizations(const Locale('ru'));
      String shape(int reviews) =>
          l10n.moduleGoalsDataCount(1, reviews).replaceAll('$reviews', '#');

      expect({shape(21), shape(3), shape(5)}, hasLength(3));
    });

    test('rows that do not decode add the unreadable sentence', () {
      final l10n = _en();

      final line = goalsDataLine(
        l10n,
        const GoalsDataCount(
          goals: 0,
          reviews: 0,
          screenings: 0,
          unreadable: 2,
        ),
      );

      expect(line, l10n.moduleGoalsDataUnreadable);
    });
  });

  group('rows that do not decode', () {
    test('count, so the delete still shows', () async {
      final db = memoryDatabase();
      await db.customStatement(
        'INSERT INTO goals (kind, started_on, block_started_on, phase, '
        'phase_since, levers) '
        "VALUES ('loseFat', '2026-11-16', '2026-11-16', 'block', "
        "'2026-11-16', 'x')",
      );
      await db.customStatement(
        "INSERT INTO goal_screenings (asked_on) VALUES ('not-a-date')",
      );
      final container = ProviderContainer.test(
        overrides: [goalStoreProvider.overrideWithValue(DriftGoalStore(db))],
      );

      final count = await container.read(goalsDataCountProvider.future);

      expect(count.goals, 0);
      expect(count.screenings, 0);
      expect(count.unreadable, 2);
      expect(count.total, 2);
    });
  });

  group('the ARB files', () {
    final arbs = {
      for (final locale in AppLocales.supported)
        locale.toString(): jsonDecode(
          File('lib/l10n/app_$locale.arb').readAsStringSync(),
        ) as Map<String, dynamic>,
    };

    for (final MapEntry(key: locale, value: arb) in arbs.entries) {
      test('$locale has the Goals keys and no dash', () {
        for (final key in [
          'moduleGoalsDataCount',
          'moduleGoalsDataScreening',
          'moduleGoalsDataEmpty',
          'privacyStoresGoals',
          'privacyStoresGoalsWhy',
        ]) {
          expect(arb.containsKey(key), isTrue, reason: key);
        }
        for (final MapEntry(:key, :value) in arb.entries) {
          if (!key.startsWith('moduleGoals') &&
              !key.startsWith('privacyStoresGoals')) {
            continue;
          }
          if (value is! String) continue;
          expect(value, isNot(contains(_emDash)), reason: key);
          expect(value, isNot(contains(_enDash)), reason: key);
        }
      });
    }

    test('Russian spells the plural forms the language needs', () {
      final message = arbs['ru']!['moduleGoalsDataCount'] as String;

      expect(message, contains('few'));
      expect(message, contains('many'));
    });

    test('Japanese and Chinese plural on other only', () {
      for (final locale in ['ja', 'zh']) {
        final message = arbs[locale]!['moduleGoalsDataCount'] as String;

        expect(message, contains('other'), reason: locale);
        expect(message, isNot(contains('few')), reason: locale);
      }
    });

    test('every locale handles zero reviews and one goal', () {
      for (final locale in arbs.keys) {
        final message = arbs[locale]!['moduleGoalsDataCount'] as String;

        expect(message, contains('{goals, plural'), reason: locale);
        expect(message, contains('{reviews, plural'), reason: locale);
      }
    });
  });
}
