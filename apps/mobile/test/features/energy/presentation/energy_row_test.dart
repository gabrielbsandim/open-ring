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
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/energy/presentation/energy_row.dart';
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

const Set<ModuleId> _on = {ModuleId.energy};

ActivitySlot _slot(int hour, int steps) => ActivitySlot(
  start: DateTime.utc(2026, 11, 10, hour),
  utcOffset: Duration.zero,
  duration: const Duration(hours: 1),
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

final List<ActivitySlot> _morningSteps = [_slot(8, 1200), _slot(9, 800)];

List<Override> _overrides({
  required DateTime Function() clock,
  UserProfile? profile = _adult,
  Set<ModuleId> modules = _on,
  bool hidden = false,
  List<ActivitySlot> slots = const [],
  ActivityHistoryReader? reader,
  List<Override> extra = const [],
}) => [
  clockProvider.overrideWithValue(clock),
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  userProfileStoreProvider.overrideWithValue(InMemoryUserProfileStore(profile)),
  hideNumbersStoreProvider.overrideWithValue(
    InMemoryHideNumbersStore(hidden: hidden),
  ),
  activityHistoryReaderProvider.overrideWithValue(
    reader ?? FakeActivityHistoryReader(const [], slots: slots),
  ),
  ...extra,
];

Future<void> _pump(
  WidgetTester tester, {
  DateTime? now,
  DateTime Function()? clock,
  UserProfile? profile = _adult,
  Set<ModuleId> modules = _on,
  bool hidden = false,
  List<ActivitySlot> slots = const [],
  ActivityHistoryReader? reader,
  List<Override> extra = const [],
  Widget child = const Scaffold(body: EnergyRowSlot()),
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) async {
  final at = now ?? _noon;
  await pumpScaled(
    tester,
    screenHost(child),
    textScaler: textScaler,
    brightness: brightness,
    locale: locale,
    overrides: _overrides(
      clock: clock ?? () => at,
      profile: profile,
      modules: modules,
      hidden: hidden,
      slots: slots,
      reader: reader,
      extra: extra,
    ),
  );
}

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(_context(tester));

MetricFormat _format(WidgetTester tester) => MetricFormat.of(_context(tester));

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(_context(tester));

Future<EnergyDayEstimate> _estimate(WidgetTester tester) async {
  final day = await _container(tester).read(energyTodayProvider.future);
  expect(day, isA<EnergyDayEstimate>());
  return day as EnergyDayEstimate;
}

DateTime _asOf(WidgetTester tester) =>
    _container(tester).read(energyAsOfProvider);

String _text(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final Text text => text.data!,
      final CaptionText text => text.text,
      final other => throw StateError('no text in ${other.runtimeType}'),
    };

String _expectedNote(WidgetTester tester) {
  final asOf = _asOf(tester);
  return _l10n(tester)
      .energyRowSoFar(_format(tester).clock(asOf, asOf.timeZoneOffset));
}

String _expectedRange(WidgetTester tester, EnergyRange range) => _l10n(tester)
    .energyRowRange(
      _format(tester).integer(range.low),
      _format(tester).integer(range.high),
    );

EnergyDayEstimate _estimateWithLow(int low) {
  for (var total = 0.0; total < 2000; total += 0.25) {
    final day = EnergyDayEstimate(
      resting: 0,
      base: total,
      steps: 0,
      workouts: 0,
    );
    if (day.range.low == low) return day;
  }
  throw StateError('no total gives a low of $low');
}

Override _today(EnergyDay day) =>
    energyTodayProvider.overrideWith((ref) async => day);

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: EnergyRowSlot()),
    ),
    GoRoute(
      path: AppPaths.settings,
      builder: (_, _) => const Scaffold(body: Text('settings')),
    ),
    GoRoute(
      path: AppPaths.energy,
      builder: (_, _) => const Scaffold(body: Text('energy')),
    ),
  ],
);

Future<void> _pumpRouted(
  WidgetTester tester,
  GoRouter router, {
  UserProfile? profile = _adult,
  DateTime? now,
}) async {
  final at = now ?? _noon;
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
    overrides: _overrides(clock: () => at, profile: profile),
  );
}

Future<void> _lifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

final class _FailingLaterReader extends FakeActivityHistoryReader {
  new() : super(const []);

  bool failing = false;

  @override
  Future<List<ActivitySlot>> activitySlots({
    required LocalDate from,
    required LocalDate to,
  }) async {
    if (failing) throw StateError('no database');
    return const [];
  }
}

const List<AppLifecycleState> _toBackground = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

const List<AppLifecycleState> _toForeground = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

void main() {
  group('the keys', () {
    test('are the ones the screens and tests share', () {
      expect(EnergyRowKeys.row, const Key('today_energy_row'));
      expect(EnergyRowKeys.note, const Key('today_energy_row_note'));
      expect(EnergyRowKeys.range, const Key('today_energy_row_range'));
      expect(EnergyRowKeys.unit, const Key('today_energy_row_unit'));
    });
  });

  group('the slot', () {
    testWidgets('shows nothing without the Energy module', (tester) async {
      await _pump(tester, modules: const {});

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('shows nothing for an underage profile', (tester) async {
      await _pump(
        tester,
        profile: const UserProfile(
          birthYear: 2026 - (energyAdultAge - 1),
          sex: Sex.male,
          heightCentimeters: 175,
          weightKilograms: 70,
        ),
      );

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('shows nothing while Body is on and numbers are hidden', (
      tester,
    ) async {
      await _pump(
        tester,
        modules: const {ModuleId.energy, ModuleId.body},
        hidden: true,
      );

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('shows the row with Body on and numbers shown', (tester) async {
      await _pump(tester, modules: const {ModuleId.energy, ModuleId.body});

      expect(find.byKey(EnergyRowKeys.row), findsOneWidget);
    });

    testWidgets('shows the row with Body off even when the hide switch is on', (
      tester,
    ) async {
      await _pump(tester, hidden: true);

      expect(find.byKey(EnergyRowKeys.row), findsOneWidget);
    });

    testWidgets('has no row and no number on the first frame', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(
            clock: () => _noon,
            modules: const {ModuleId.energy, ModuleId.body},
            slots: _morningSteps,
          ),
          child: screenHost(const Scaffold(body: EnergyRowSlot())),
        ),
      );

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
      expect(find.byKey(EnergyRowKeys.range), findsNothing);

      await tester.pumpAndSettle();

      expect(find.byKey(EnergyRowKeys.row), findsOneWidget);
    });
  });

  group('the estimate', () {
    testWidgets('shows the title, the range, the unit and the time', (
      tester,
    ) async {
      await _pump(tester, slots: _morningSteps);
      final day = await _estimate(tester);

      expect(day.range.low, greaterThanOrEqualTo(energyRowFloor));
      expect(find.text(_l10n(tester).energyTitle), findsOneWidget);
      expect(
        _text(tester, EnergyRowKeys.range),
        _expectedRange(tester, day.range),
      );
      expect(_text(tester, EnergyRowKeys.unit), _l10n(tester).energyRowUnit);
      expect(_text(tester, EnergyRowKeys.note), _expectedNote(tester));
    });

    testWidgets('reads in English as two grouped numbers and a unit', (
      tester,
    ) async {
      await _pump(tester, now: _evening, slots: _morningSteps);

      expect(
        _text(tester, EnergyRowKeys.range),
        matches(RegExp(r'^\d{1,3}(,\d{3})* to \d{1,3}(,\d{3})*$')),
      );
      expect(_text(tester, EnergyRowKeys.unit), 'kcal, estimate');
      expect(_text(tester, EnergyRowKeys.note), 'So far · 20:00');
    });

    testWidgets('groups the thousands the way the locale does in German', (
      tester,
    ) async {
      await _pump(
        tester,
        now: _evening,
        slots: _morningSteps,
        locale: const Locale('de'),
      );
      final day = await _estimate(tester);

      expect(day.range.low, greaterThanOrEqualTo(1000));
      expect(
        _text(tester, EnergyRowKeys.range),
        _expectedRange(tester, day.range),
      );
      expect(_text(tester, EnergyRowKeys.range), contains('.'));
      expect(_text(tester, EnergyRowKeys.range), isNot(contains(',')));
    });

    testWidgets('tapping the card opens the Energy screen', (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pumpRouted(tester, router);

      await tester.tap(find.byKey(EnergyRowKeys.row));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppPaths.energy);
    });

    testWidgets('the semantics offer the tap', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        tester.getSemantics(find.byKey(EnergyRowKeys.row)),
        isSemantics(isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('the semantics label names the range and the estimate', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, slots: _morningSteps);
      final day = await _estimate(tester);
      final format = _format(tester);

      final label = tester.getSemantics(find.byKey(EnergyRowKeys.row)).label;

      expect(
        label,
        contains(
          _l10n(tester).energyRowSemantics(
            format.integer(day.range.low),
            format.integer(day.range.high),
          ),
        ),
      );
      handle.dispose();
    });

    testWidgets('a low exactly at the floor still shows the range', (
      tester,
    ) async {
      final day = _estimateWithLow(energyRowFloor);

      await _pump(tester, extra: [_today(day)]);

      expect(find.byKey(EnergyRowKeys.range), findsOneWidget);
      expect(find.byKey(EnergyRowKeys.unit), findsOneWidget);
    });
  });

  group('under the floor', () {
    testWidgets('a few minutes after midnight shows the starting line', (
      tester,
    ) async {
      await _pump(tester, now: _justAfterMidnight);
      final day = await _estimate(tester);

      expect(day.range.low, lessThan(energyRowFloor));
      expect(
        _text(tester, EnergyRowKeys.note),
        _l10n(tester).energyRowStarting,
      );
      expect(find.byKey(EnergyRowKeys.range), findsNothing);
      expect(find.byKey(EnergyRowKeys.unit), findsNothing);
    });

    testWidgets('says the day is just starting in English', (tester) async {
      await _pump(tester, now: _justAfterMidnight);

      expect(_text(tester, EnergyRowKeys.note), 'The day is just starting');
    });

    testWidgets('a low one step below the floor has no range', (tester) async {
      final day = _estimateWithLow(energyRowFloor - energyRangeStep);

      await _pump(tester, extra: [_today(day)]);

      expect(find.byKey(EnergyRowKeys.range), findsNothing);
      expect(find.byKey(EnergyRowKeys.unit), findsNothing);
      expect(
        _text(tester, EnergyRowKeys.note),
        _l10n(tester).energyRowStarting,
      );
    });

    testWidgets('tapping the card opens the Energy screen', (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pumpRouted(tester, router, now: _justAfterMidnight);

      await tester.tap(find.byKey(EnergyRowKeys.row));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppPaths.energy);
    });
  });

  group('a missing field', () {
    final cases = <String, (UserProfile?, String Function(AppLocalizations))>{
      'age': (
        const UserProfile(
          sex: Sex.male,
          heightCentimeters: 175,
          weightKilograms: 70,
        ),
        (l10n) => l10n.energyRowMissingAge,
      ),
      'height': (
        const UserProfile(birthYear: 1996, sex: Sex.male, weightKilograms: 70),
        (l10n) => l10n.energyRowMissingHeight,
      ),
      'weight': (
        const UserProfile(
          birthYear: 1996,
          sex: Sex.male,
          heightCentimeters: 175,
        ),
        (l10n) => l10n.energyRowMissingWeight,
      ),
      'sex': (
        const UserProfile(
          birthYear: 1996,
          heightCentimeters: 175,
          weightKilograms: 70,
        ),
        (l10n) => l10n.energyRowMissingSex,
      ),
    };

    for (final entry in cases.entries) {
      testWidgets('the ${entry.key} has its own line', (tester) async {
        await _pump(tester, profile: entry.value.$1);

        expect(
          _text(tester, EnergyRowKeys.note),
          entry.value.$2(_l10n(tester)),
        );
        expect(find.byKey(EnergyRowKeys.range), findsNothing);
        expect(find.byKey(EnergyRowKeys.unit), findsNothing);
      });
    }

    testWidgets('the sex line reads as the spec words it', (tester) async {
      await _pump(tester, profile: cases['sex']!.$1);

      expect(
        _text(tester, EnergyRowKeys.note),
        'Choose Female or Male to see an estimate',
      );
    });

    testWidgets('two missing fields show the several line', (tester) async {
      await _pump(
        tester,
        profile: const UserProfile(birthYear: 1996, sex: Sex.male),
      );

      expect(
        _text(tester, EnergyRowKeys.note),
        _l10n(tester).energyRowMissingSeveral,
      );
      expect(find.byKey(EnergyRowKeys.range), findsNothing);
      expect(find.byKey(EnergyRowKeys.unit), findsNothing);
    });

    testWidgets('no profile at all shows the several line', (tester) async {
      await _pump(tester, profile: null);

      expect(
        _text(tester, EnergyRowKeys.note),
        _l10n(tester).energyRowMissingSeveral,
      );
    });

    testWidgets('tapping the card opens the settings', (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pumpRouted(tester, router, profile: cases['height']!.$1);

      await tester.tap(find.byKey(EnergyRowKeys.row));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppPaths.settings);
    });

    testWidgets('tapping the several line also opens the settings', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pumpRouted(tester, router, profile: null);

      await tester.tap(find.byKey(EnergyRowKeys.row));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppPaths.settings);
    });
  });

  group('loading, error and underage', () {
    testWidgets('while the day loads there is no row', (tester) async {
      final never = Completer<EnergyDay>();
      await _pump(
        tester,
        child: const Scaffold(body: EnergyRow()),
        extra: [energyTodayProvider.overrideWith((ref) => never.future)],
      );

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
      expect(find.byKey(EnergyRowKeys.range), findsNothing);
    });

    testWidgets('when the day fails there is no row', (tester) async {
      await _pump(
        tester,
        child: const Scaffold(body: EnergyRow()),
        extra: [
          energyTodayProvider.overrideWith(
            (ref) async => throw StateError('no database'),
          ),
        ],
      );

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('for an underage day there is no row', (tester) async {
      await _pump(
        tester,
        child: const Scaffold(body: EnergyRow()),
        extra: [_today(const EnergyDayUnderage())],
      );

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('the slot shows no row while the day loads', (tester) async {
      final never = Completer<EnergyDay>();
      await _pump(
        tester,
        extra: [energyTodayProvider.overrideWith((ref) => never.future)],
      );

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('the slot shows no row when the day fails', (tester) async {
      await _pump(
        tester,
        extra: [
          energyTodayProvider.overrideWith(
            (ref) async => throw StateError('no database'),
          ),
        ],
      );

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });
  });

  group('on resume', () {
    testWidgets('the note and the range follow the later clock', (
      tester,
    ) async {
      var now = _noon;
      await _pump(tester, clock: () => now, slots: _morningSteps);
      final before = await _estimate(tester);
      final noteBefore = _text(tester, EnergyRowKeys.note);
      await _lifecycle(tester, _toBackground);

      now = _evening;
      await _lifecycle(tester, _toForeground);
      await tester.pumpAndSettle();
      final after = await _estimate(tester);

      expect(_asOf(tester), _evening);
      expect(_text(tester, EnergyRowKeys.note), isNot(noteBefore));
      expect(_text(tester, EnergyRowKeys.note), _expectedNote(tester));
      expect(after.range.high, greaterThan(before.range.high));
      expect(
        _text(tester, EnergyRowKeys.range),
        _expectedRange(tester, after.range),
      );
    });

    testWidgets('a later clock alone changes nothing until the app resumes', (
      tester,
    ) async {
      var now = _noon;
      await _pump(tester, clock: () => now, slots: _morningSteps);
      final noteBefore = _text(tester, EnergyRowKeys.note);
      final rangeBefore = _text(tester, EnergyRowKeys.range);

      now = _evening;
      await tester.pump(const Duration(hours: 1));

      expect(_text(tester, EnergyRowKeys.note), noteBefore);
      expect(_text(tester, EnergyRowKeys.range), rangeBefore);
    });

    testWidgets('a resume after midnight starts the new day', (tester) async {
      var now = DateTime.utc(2026, 11, 10, 23, 50);
      await _pump(tester, clock: () => now, slots: _morningSteps);
      expect(find.byKey(EnergyRowKeys.range), findsOneWidget);
      await _lifecycle(tester, _toBackground);

      now = DateTime.utc(2026, 11, 11, 0, 5);
      await _lifecycle(tester, _toForeground);
      await tester.pumpAndSettle();

      expect(
        _text(tester, EnergyRowKeys.note),
        _l10n(tester).energyRowStarting,
      );
      expect(find.byKey(EnergyRowKeys.range), findsNothing);
    });

    testWidgets('a person who comes of age in the new year gets the row', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 12, 31, 20);
      await _pump(
        tester,
        clock: () => now,
        profile: const UserProfile(
          birthYear: 2027 - energyAdultAge,
          sex: Sex.male,
          heightCentimeters: 175,
          weightKilograms: 70,
        ),
      );
      expect(find.byKey(EnergyRowKeys.row), findsNothing);
      await _lifecycle(tester, _toBackground);

      now = DateTime.utc(2027, 1, 1, 12);
      await _lifecycle(tester, _toForeground);
      await tester.pumpAndSettle();

      expect(find.byKey(EnergyRowKeys.range), findsOneWidget);
    });

    testWidgets('a day that fails after one that worked leaves no row', (
      tester,
    ) async {
      var now = _noon;
      final reader = _FailingLaterReader();
      await _pump(tester, clock: () => now, reader: reader);
      await _lifecycle(tester, _toBackground);

      reader.failing = true;
      now = _evening;
      await _lifecycle(tester, _toForeground);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(EnergyRowKeys.row), findsNothing);
    });

    testWidgets('a row that was starting shows the range after resume', (
      tester,
    ) async {
      var now = _justAfterMidnight;
      await _pump(tester, clock: () => now);
      expect(find.byKey(EnergyRowKeys.range), findsNothing);
      await _lifecycle(tester, _toBackground);

      now = _evening;
      await _lifecycle(tester, _toForeground);
      await tester.pumpAndSettle();

      expect(find.byKey(EnergyRowKeys.range), findsOneWidget);
    });
  });

  group('layout', () {
    final states = <String, ({DateTime now, UserProfile? profile})>{
      'an estimate': (now: _evening, profile: _adult),
      'the starting line': (now: _justAfterMidnight, profile: _adult),
      'several missing fields': (now: _noon, profile: null),
    };

    for (final layout in layoutMatrix()) {
      for (final state in states.entries) {
        testWidgets('fits $layout with ${state.key}', (tester) async {
          await _pump(
            tester,
            now: state.value.now,
            profile: state.value.profile,
            slots: _morningSteps,
            locale: layout.locale,
            textScaler: layout.textScaler,
            brightness: layout.brightness,
          );

          expect(find.byKey(EnergyRowKeys.row), findsOneWidget);
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
              now: state.value.now,
              profile: state.value.profile,
              slots: _morningSteps,
              locale: locale,
              textScaler: TextScaler.linear(scale),
            );

            expect(find.byKey(EnergyRowKeys.row), findsOneWidget);
          });
        }
      }
    }
  });
}
