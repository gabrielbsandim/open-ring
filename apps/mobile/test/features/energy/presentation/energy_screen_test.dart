import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_evidence_sheet.dart';
import 'package:open_ring/features/energy/presentation/energy_parts.dart';
import 'package:open_ring/features/energy/presentation/energy_screen.dart';
import 'package:open_ring/features/energy/presentation/energy_through_day.dart';
import 'package:open_ring/features/energy/presentation/energy_week.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';

final DateTime _noon = DateTime.utc(2026, 11, 10, 12);
final DateTime _evening = DateTime.utc(2026, 11, 10, 20);
final DateTime _justAfterMidnight = DateTime.utc(2026, 11, 10, 0, 5);

const UserProfile _adult = UserProfile(
  birthYear: 1996,
  sex: Sex.male,
  heightCentimeters: 175,
  weightKilograms: 70,
);

const EnergyDayEstimate _full = EnergyDayEstimate(
  resting: 1700,
  base: 1100,
  steps: 180,
  workouts: 304,
);

const EnergyDayEstimate _noWorkout = EnergyDayEstimate(
  resting: 1700,
  base: 1100,
  steps: 180,
  workouts: 0,
);

const EnergyDayEstimate _early = EnergyDayEstimate(
  resting: 1700,
  base: 8,
  steps: 0,
  workouts: 0,
);

ActivitySlot _slot(int hour, int steps) => ActivitySlot(
  start: DateTime.utc(2026, 11, 10, hour),
  utcOffset: Duration.zero,
  duration: const Duration(hours: 1),
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

Override _today(EnergyDay day) =>
    energyTodayProvider.overrideWith((ref) async => day);

List<Override> _overrides({
  required DateTime now,
  UserProfile? profile = _adult,
  Set<ModuleId> modules = const {ModuleId.energy},
  bool hidden = false,
  List<ActivitySlot> slots = const [],
  List<Override> extra = const [],
}) => [
  clockProvider.overrideWithValue(() => now),
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  userProfileStoreProvider.overrideWithValue(InMemoryUserProfileStore(profile)),
  hideNumbersStoreProvider.overrideWithValue(
    InMemoryHideNumbersStore(hidden: hidden),
  ),
  activityHistoryReaderProvider.overrideWithValue(
    FakeActivityHistoryReader(const [], slots: slots),
  ),
  ...extra,
];

Future<void> _pump(
  WidgetTester tester, {
  DateTime? now,
  EnergyDay? day,
  UserProfile? profile = _adult,
  Set<ModuleId> modules = const {ModuleId.energy},
  bool hidden = false,
  List<ActivitySlot> slots = const [],
  List<Override> extra = const [],
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(const EnergyScreen()),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: _overrides(
    now: now ?? _noon,
    profile: profile,
    modules: modules,
    hidden: hidden,
    slots: slots,
    extra: [if (day != null) _today(day), ...extra],
  ),
);

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(EnergyScreen));

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(_context(tester));

MetricFormat _format(WidgetTester tester) => MetricFormat.of(_context(tester));

String _text(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data!,
      final CaptionText text => text.text,
      final BodyText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

String _range(WidgetTester tester, EnergyRange range) => _l10n(tester)
    .energyRowRange(
      _format(tester).integer(range.low),
      _format(tester).integer(range.high),
    );

List<double> _weights(WidgetTester tester) => [
  for (final segment
      in tester.widget<SegmentedBar>(find.byKey(EnergyKeys.bar)).segments)
    segment.weight,
];

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 100);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('the gate', () {
    testWidgets('shows only the title without the Energy module', (
      tester,
    ) async {
      await _pump(tester, day: _full, modules: const {});

      expect(find.text(_l10n(tester).energyTitle), findsOneWidget);
      expect(find.text(_l10n(tester).energyLead), findsNothing);
      expect(find.byKey(EnergyKeys.day), findsNothing);
      expect(find.byKey(EnergyKeys.resting), findsNothing);
    });

    testWidgets('shows no card while Body hides the numbers', (tester) async {
      await _pump(
        tester,
        day: _full,
        modules: const {ModuleId.energy, ModuleId.body},
        hidden: true,
      );

      expect(find.byKey(EnergyKeys.day), findsNothing);
      expect(find.byKey(EnergyKeys.resting), findsNothing);
    });

    testWidgets('shows no card for an underage profile', (tester) async {
      await _pump(
        tester,
        day: _full,
        profile: const UserProfile(
          birthYear: 2010,
          sex: Sex.male,
          heightCentimeters: 175,
          weightKilograms: 70,
        ),
      );

      expect(find.byKey(EnergyKeys.day), findsNothing);
      expect(find.byKey(EnergyKeys.resting), findsNothing);
    });

    testWidgets('an underage day shows no card either', (tester) async {
      await _pump(tester, day: const EnergyDayUnderage());

      expect(find.byKey(EnergyKeys.day), findsNothing);
      expect(find.byKey(EnergyKeys.missing), findsNothing);
    });
  });

  group('the day', () {
    testWidgets('shows the range, the time and the middle', (tester) async {
      await _pump(tester, day: _full, now: _evening);
      final format = _format(tester);

      expect(_text(tester, EnergyKeys.range), _range(tester, _full.range));
      expect(
        _text(tester, EnergyKeys.time),
        _l10n(tester).energyRowSoFar(format.clock(_evening, Duration.zero)),
      );
      expect(
        _text(tester, EnergyKeys.middle),
        _l10n(tester).energyDayMiddle(format.integer(1600)),
      );
    });

    testWidgets('the range is the one of the day the providers compute', (
      tester,
    ) async {
      await _pump(tester, slots: [_slot(8, 1200), _slot(9, 800)]);
      final container = ProviderScope.containerOf(_context(tester));
      final day = await container.read(energyTodayProvider.future);

      expect(day, isA<EnergyDayEstimate>());
      expect(
        _text(tester, EnergyKeys.range),
        _range(tester, (day as EnergyDayEstimate).range),
      );
    });

    testWidgets('each part prints to the nearest ten with the word about', (
      tester,
    ) async {
      await _pump(tester, day: _full);
      final l10n = _l10n(tester);

      expect(
        _text(tester, EnergyKeys.partValue(EnergyPart.base)),
        l10n.energyPartAbout('1,100'),
      );
      expect(
        _text(tester, EnergyKeys.partValue(EnergyPart.steps)),
        l10n.energyPartAbout('180'),
      );
      expect(
        _text(tester, EnergyKeys.partValue(EnergyPart.workouts)),
        l10n.energyPartAbout('300'),
      );
      expect(find.text(l10n.energyPartWorkoutsNote), findsOneWidget);
    });

    testWidgets('a day without a workout says so and draws no segment', (
      tester,
    ) async {
      await _pump(tester, day: _noWorkout);
      final l10n = _l10n(tester);

      expect(
        _text(tester, EnergyKeys.partValue(EnergyPart.workouts)),
        l10n.energyKcal('0'),
      );
      expect(find.text(l10n.energyPartWorkoutsNone), findsOneWidget);
      expect(find.text(l10n.energyPartWorkoutsNote), findsNothing);
      expect(_weights(tester)[EnergyPart.workouts.index], 0);
    });

    testWidgets('the bar weighs the three parts against the bar scale', (
      tester,
    ) async {
      await _pump(tester, day: _full);

      expect(_weights(tester), [1100, 180, 304, energyBarScale(_full) - 1584]);
    });

    testWidgets('a day past the scale leaves no empty track', (tester) async {
      const big = EnergyDayEstimate(
        resting: 1700,
        base: 2210,
        steps: 900,
        workouts: 1500,
      );
      await _pump(tester, day: big);

      expect(energyBarScale(big), big.range.high);
      expect(_weights(tester).last, big.range.high - big.total);
      expect(_weights(tester).every((weight) => weight >= 0), isTrue);
    });

    testWidgets('the bar reads as the range to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, day: _full);
      final format = _format(tester);

      expect(
        find.bySemanticsLabel(
          _l10n(tester).energyBarSemantics(
            format.integer(_full.range.low),
            format.integer(_full.range.high),
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('under the floor it says the day is starting, no number', (
      tester,
    ) async {
      await _pump(tester, day: _early, now: _justAfterMidnight);

      expect(_early.range.low, lessThan(energyRowFloor));
      expect(
        _text(tester, EnergyKeys.starting),
        _l10n(tester).energyRowStarting,
      );
      expect(find.byKey(EnergyKeys.range), findsNothing);
      expect(find.byKey(EnergyKeys.bar), findsNothing);
      expect(find.byKey(EnergyKeys.part(EnergyPart.base)), findsNothing);
      expect(find.byKey(EnergyKeys.resting), findsOneWidget);
    });
  });

  group('the resting burn', () {
    testWidgets('shows the resting figure as a ten percent range', (
      tester,
    ) async {
      await _pump(tester, day: _full);
      await _reveal(tester, find.byKey(EnergyKeys.restingBase));

      expect(
        _text(tester, EnergyKeys.restingRange),
        _range(tester, (low: 1550, high: 1850)),
      );
      expect(
        _text(tester, EnergyKeys.restingBase),
        _l10n(tester).energyRestingBase('1.3'),
      );
    });

    testWidgets('the exact resting figure is nowhere on the screen', (
      tester,
    ) async {
      await _pump(tester, day: _full);

      expect(find.textContaining('1,700'), findsNothing);
      expect(find.textContaining('1700'), findsNothing);
    });
  });

  group('through the day', () {
    testWidgets('the card shows the day the providers compute', (tester) async {
      await _pump(tester, slots: [_slot(8, 1200), _slot(9, 800)]);
      await _reveal(tester, find.byKey(EnergyThroughKeys.range));
      final container = ProviderScope.containerOf(_context(tester));
      final day = await container.read(energyTodayProvider.future);
      final curve = await container.read(energyTodayCurveProvider.future);

      expect(curve.points, hasLength(13));
      expect(curve.points.last.day.total, (day as EnergyDayEstimate).total);
      expect(
        _text(tester, EnergyThroughKeys.range),
        _l10n(tester).energyKcal(_range(tester, day.range)),
      );
    });

    testWidgets('there is no card while the day is under the floor', (
      tester,
    ) async {
      await _pump(tester, now: _justAfterMidnight);
      await tester.scrollUntilVisible(find.byKey(EnergyKeys.never), 100);

      expect(find.byKey(EnergyThroughKeys.card), findsNothing);
    });

    testWidgets('there is no card for a day with a missing fact', (
      tester,
    ) async {
      await _pump(tester, profile: null);

      expect(find.byKey(EnergyKeys.missing), findsOneWidget);
      expect(find.byKey(EnergyThroughKeys.card), findsNothing);
    });
  });

  group('the last 7 days', () {
    testWidgets('are absent while no past day has anything on record', (
      tester,
    ) async {
      await _pump(tester, slots: [_slot(8, 1200)]);
      await _reveal(tester, find.byKey(EnergyKeys.never));

      expect(find.byType(EnergyWeek, skipOffstage: false), findsNothing);
    });

    testWidgets('show once a past day has steps', (tester) async {
      await _pump(
        tester,
        slots: [
          _slot(8, 1200),
          ActivitySlot(
            start: DateTime.utc(2026, 11, 8, 9),
            utcOffset: Duration.zero,
            duration: const Duration(hours: 1),
            steps: 4000,
            activeKilocalories: 0,
            distanceMeters: 0,
          ),
        ],
      );
      await _reveal(tester, find.byKey(EnergyWeekKeys.card));
      final week = tester.widget<EnergyWeek>(find.byType(EnergyWeek));

      expect(week.days, hasLength(energyWeekDays));
      expect(week.days[4].day, isNotNull);
      expect(week.days[5].day, isNull);
    });
  });

  group('the evidence', () {
    for (final part in EnergyPart.values) {
      testWidgets('a tap on ${part.name} opens its sheet', (tester) async {
        await _pump(tester, day: _full);
        await _reveal(tester, find.byKey(EnergyKeys.part(part)));

        await tester.tap(find.byKey(EnergyKeys.part(part)));
        await tester.pumpAndSettle();

        final sheet = tester.widget<EnergyEvidenceSheet>(
          find.byType(EnergyEvidenceSheet),
        );
        expect(sheet.kind, energyEvidenceOf(part));
        expect(sheet.day, _full);
      });
    }

    testWidgets('a tap on the resting burn opens its sheet', (tester) async {
      await _pump(tester, day: _full);
      await _reveal(tester, find.byKey(EnergyKeys.restingRange));

      await tester.tap(find.byKey(EnergyKeys.restingRange));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<EnergyEvidenceSheet>(find.byType(EnergyEvidenceSheet))
            .kind,
        EnergyEvidence.resting,
      );
    });
  });

  group('what it never does', () {
    testWidgets('lists the four rules', (tester) async {
      await _pump(tester, day: _full);
      final l10n = _l10n(tester);
      await tester.scrollUntilVisible(find.text(l10n.energyNever4), 200);

      for (final rule in [
        l10n.energyNever1,
        l10n.energyNever2,
        l10n.energyNever3,
        l10n.energyNever4,
      ]) {
        expect(find.text(rule), findsOneWidget);
      }
    });
  });

  group('a missing profile fact', () {
    testWidgets('one missing fact is named and marked', (tester) async {
      await _pump(tester, day: const EnergyDayMissing({EnergyField.height}));
      final l10n = _l10n(tester);

      expect(
        _text(tester, EnergyKeys.missingTitle),
        l10n.energyMissingTitleOne,
      );
      expect(
        find.byKey(EnergyKeys.needMissing(EnergyField.height)),
        findsOneWidget,
      );
      for (final field in EnergyField.values) {
        expect(find.byKey(EnergyKeys.need(field)), findsOneWidget);
      }
      expect(
        find.byKey(EnergyKeys.needMissing(EnergyField.weight)),
        findsNothing,
      );
      expect(find.byKey(EnergyKeys.day), findsNothing);
      expect(find.byKey(EnergyKeys.resting), findsNothing);
    });

    testWidgets('a profile with no sex chosen marks the sex', (tester) async {
      await _pump(
        tester,
        profile: const UserProfile(
          birthYear: 1996,
          heightCentimeters: 175,
          weightKilograms: 70,
        ),
      );

      expect(
        find.byKey(EnergyKeys.needMissing(EnergyField.sex)),
        findsOneWidget,
      );
      expect(
        find.byKey(EnergyKeys.needMissing(EnergyField.birthYear)),
        findsNothing,
      );
    });

    testWidgets('several missing facts use the several title', (tester) async {
      await _pump(
        tester,
        day: const EnergyDayMissing({EnergyField.height, EnergyField.sex}),
      );

      expect(
        _text(tester, EnergyKeys.missingTitle),
        _l10n(tester).energyMissingTitleSeveral,
      );
    });

    testWidgets('the button opens the settings', (tester) async {
      final router = GoRouter(
        initialLocation: AppPaths.energy,
        routes: [
          GoRoute(
            path: AppPaths.energy,
            builder: (_, _) => const EnergyScreen(),
          ),
          GoRoute(
            path: AppPaths.settings,
            builder: (_, _) => const Scaffold(body: Text('settings')),
          ),
        ],
      );
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
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: _overrides(
          now: _noon,
          extra: [
            _today(const EnergyDayMissing({EnergyField.weight})),
          ],
        ),
      );

      await _reveal(tester, find.byKey(EnergyKeys.openProfile));
      await tester.tap(find.byKey(EnergyKeys.openProfile));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppPaths.settings);
    });
  });

  group('loading and error', () {
    testWidgets('while the day loads there is no card', (tester) async {
      final never = Completer<EnergyDay>();
      await _pump(
        tester,
        extra: [energyTodayProvider.overrideWith((ref) => never.future)],
      );

      expect(find.byKey(EnergyKeys.day), findsNothing);
      expect(find.byKey(EnergyKeys.missing), findsNothing);
      expect(find.text(_l10n(tester).metricLoadError), findsNothing);
    });

    testWidgets('when the day fails it says the data could not be read', (
      tester,
    ) async {
      await _pump(
        tester,
        extra: [
          energyTodayProvider.overrideWith(
            (ref) async => throw StateError('no database'),
          ),
        ],
      );

      expect(find.text(_l10n(tester).metricLoadError), findsOneWidget);
      expect(find.byKey(EnergyKeys.day), findsNothing);
    });
  });

  group('layout', () {
    final states = <String, (EnergyDay, Key)>{
      'an estimate': (_full, EnergyKeys.day),
      'the starting line': (_early, EnergyKeys.day),
      'missing facts': (
        const EnergyDayMissing({EnergyField.height, EnergyField.sex}),
        EnergyKeys.missing,
      ),
    };

    for (final layout in layoutMatrix()) {
      for (final state in states.entries) {
        testWidgets('fits $layout with ${state.key}', (tester) async {
          await _pump(
            tester,
            day: state.value.$1,
            locale: layout.locale,
            textScaler: layout.textScaler,
            brightness: layout.brightness,
          );

          await tester.scrollUntilVisible(find.byKey(state.value.$2), 100);
          expect(find.byKey(state.value.$2), findsOneWidget);
        });
      }
    }

    for (final scale in [1.6, 2.0]) {
      for (final locale in AppLocales.supported) {
        for (final state in states.entries) {
          testWidgets('fits ${scale}x in $locale with ${state.key}', (
            tester,
          ) async {
            await _pump(
              tester,
              day: state.value.$1,
              locale: locale,
              textScaler: TextScaler.linear(scale),
            );

            await tester.scrollUntilVisible(find.byKey(state.value.$2), 100);
            expect(find.byKey(state.value.$2), findsOneWidget);
          });
        }
      }
    }
  });
}
