import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/module_change.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/in_memory_projection_store.dart';
import 'package:open_ring/features/trajectory/domain/projection_store.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_module_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

final DateTime _now = DateTime.utc(2026, 11, 26, 12);

UserProfile _aged(int age) => UserProfile(
  birthYear: UserProfile.birthYearFor(age, year: _now.year),
  sex: Sex.female,
  heightCentimeters: 165,
  weightKilograms: 70,
);

TrajectoryProjection _projection(LocalDate monday) => TrajectoryProjection(
  monday: monday,
  trendKg: 70,
  rateKgPerWeek: -0.3,
  lowKg: 68.4,
  midKg: 68.8,
  highKg: 69.3,
  createdAt: _now,
);

final class _Store implements ProjectionStore {
  new(this._inner, {this.failDelete = false, this.failRead = false});

  final InMemoryProjectionStore _inner;
  final bool failDelete;
  final bool failRead;

  @override
  Future<bool> insertIfAbsent(TrajectoryProjection projection) =>
      _inner.insertIfAbsent(projection);

  @override
  Future<List<TrajectoryProjection>> all() =>
      failRead ? Future.error(StateError('disk')) : _inner.all();

  @override
  Future<int> deleteAll() =>
      failDelete ? Future.error(StateError('disk')) : _inner.deleteAll();
}

Future<InMemoryProjectionStore> _seeded() async {
  final store = InMemoryProjectionStore();
  await store.insertIfAbsent(_projection(const LocalDate(2026, 11, 16)));
  await store.insertIfAbsent(_projection(const LocalDate(2026, 11, 23)));
  return store;
}

Future<void> _pump(
  WidgetTester tester, {
  required InMemoryModuleStore modules,
  ProjectionStore? projections,
  UserProfile? profile,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final router = GoRouter(
    initialLocation: AppPaths.settingsModuleTrajectory,
    routes: [
      GoRoute(
        path: AppPaths.settingsModuleTrajectory,
        builder: (_, _) => const TrajectoryModuleScreen(),
      ),
      GoRoute(
        path: AppPaths.trajectory,
        builder: (_, _) => const Scaffold(body: Text('trajectory')),
      ),
      GoRoute(
        path: AppPaths.trajectoryFormula,
        builder: (_, _) => const Scaffold(body: Text('formula')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await pumpScaled(
    tester,
    MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      supportedLocales: AppLocales.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    ),
    textScaler: textScaler,
    brightness: Brightness.dark,
    locale: locale,
    overrides: <Override>[
      clockProvider.overrideWithValue(() => _now),
      moduleStoreProvider.overrideWithValue(modules),
      userProfileStoreProvider.overrideWithValue(
        InMemoryUserProfileStore(profile ?? _aged(40)),
      ),
      projectionStoreProvider.overrideWithValue(
        projections ?? InMemoryProjectionStore(),
      ),
    ],
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TrajectoryModuleScreen)));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 300,
  );
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, Key key) => find
    .descendant(of: find.byKey(key), matching: find.byType(Text))
    .evaluate()
    .map((element) => (element.widget as Text).data ?? '')
    .join(' ');

void main() {
  testWidgets('off with Body on: Turn on, the note and nothing stored', (
    tester,
  ) async {
    await _pump(tester, modules: InMemoryModuleStore({ModuleId.body}));
    final l10n = _l10n(tester);

    expect(_text(tester, TrajectoryModuleKeys.state), l10n.modulesOff);
    expect(find.byKey(TrajectoryModuleKeys.needsBody), findsNothing);
    expect(find.byKey(TrajectoryModuleKeys.view), findsNothing);
    await _reveal(tester, find.byKey(TrajectoryModuleKeys.toggle));
    expect(find.text(l10n.moduleTrajectoryDataEmpty), findsOneWidget);
    expect(find.byKey(TrajectoryModuleKeys.delete), findsNothing);
    expect(find.text(l10n.moduleTrajectoryTurnOn), findsOneWidget);
    expect(find.text(l10n.moduleTrajectoryTurnOnNote), findsOneWidget);
  });

  testWidgets('Body off: the notice and one button that asks for both', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    await _pump(tester, modules: modules);
    final l10n = _l10n(tester);
    final body = l10n.moduleBodyName;

    expect(find.text(l10n.moduleTrajectoryNeedsBody(body)), findsOneWidget);
    await _reveal(tester, find.byKey(TrajectoryModuleKeys.toggle));
    expect(find.text(l10n.moduleTrajectoryTurnOnBoth(body)), findsOneWidget);
    expect(
      find.text(l10n.moduleTrajectoryTurnOnBothNote(body)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(TrajectoryModuleKeys.toggle));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ModuleChangeKeys.confirm));
    await tester.pumpAndSettle();

    expect(await modules.read(), {ModuleId.body, ModuleId.trajectory});
    expect(find.text(l10n.moduleTrajectoryTurnOff), findsOneWidget);
  });

  testWidgets('under 18: the notice, Not available and no button', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.body}),
      profile: _aged(17),
    );
    final l10n = _l10n(tester);

    expect(
      _text(tester, TrajectoryModuleKeys.state),
      l10n.moduleEnergyUnavailable,
    );
    expect(find.text(l10n.trajectoryRefusedUnderage), findsOneWidget);
    expect(find.byKey(TrajectoryModuleKeys.needsBody), findsNothing);
    await _reveal(tester, find.text(l10n.moduleBodyFoot));
    expect(find.byKey(TrajectoryModuleKeys.toggle), findsNothing);
  });

  testWidgets('on: the count, the links and Turn off with its note', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.body, ModuleId.trajectory}),
      projections: await _seeded(),
    );
    final l10n = _l10n(tester);

    expect(_text(tester, TrajectoryModuleKeys.state), l10n.modulesOn);
    await _reveal(tester, find.byKey(TrajectoryModuleKeys.stored));
    expect(find.byKey(TrajectoryModuleKeys.view), findsOneWidget);
    expect(find.byKey(TrajectoryModuleKeys.formula), findsOneWidget);
    expect(
      _text(tester, TrajectoryModuleKeys.stored),
      allOf(contains(': 2,'), contains('16'), contains('23')),
    );
    await _reveal(tester, find.byKey(TrajectoryModuleKeys.toggle));
    expect(find.text(l10n.moduleTrajectoryTurnOff), findsOneWidget);
    expect(
      find.text(l10n.moduleTrajectoryTurnOffNote(l10n.moduleBodyName)),
      findsOneWidget,
    );
  });

  testWidgets('delete asks once, empties the store and keeps the module on', (
    tester,
  ) async {
    final modules = InMemoryModuleStore({ModuleId.body, ModuleId.trajectory});
    final store = await _seeded();
    await _pump(tester, modules: modules, projections: store);
    final l10n = _l10n(tester);

    await _reveal(tester, find.byKey(TrajectoryModuleKeys.delete));
    await tester.tap(find.byKey(TrajectoryModuleKeys.delete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.moduleTrajectoryDeleteBody(2)), findsOneWidget);
    expect(
      find.text(l10n.moduleTrajectoryDeleteFact1(l10n.moduleBodyName)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(TrajectoryModuleKeys.deleteConfirm));
    await tester.pumpAndSettle();

    expect(await store.all(), isEmpty);
    expect(await modules.read(), {ModuleId.body, ModuleId.trajectory});
    expect(find.text(l10n.moduleTrajectoryDeleted), findsOneWidget);
    expect(find.text(l10n.moduleTrajectoryDataEmpty), findsOneWidget);
    expect(find.byKey(TrajectoryModuleKeys.delete), findsNothing);
  });

  testWidgets('cancel keeps every projection', (tester) async {
    final store = await _seeded();
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.body, ModuleId.trajectory}),
      projections: store,
    );

    await _reveal(tester, find.byKey(TrajectoryModuleKeys.delete));
    await tester.tap(find.byKey(TrajectoryModuleKeys.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TrajectoryModuleKeys.deleteCancel));
    await tester.pumpAndSettle();

    expect(await store.all(), hasLength(2));
  });

  testWidgets('a failed delete says so and keeps the button', (tester) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.body, ModuleId.trajectory}),
      projections: _Store(await _seeded(), failDelete: true),
    );
    final l10n = _l10n(tester);

    await _reveal(tester, find.byKey(TrajectoryModuleKeys.delete));
    await tester.tap(find.byKey(TrajectoryModuleKeys.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TrajectoryModuleKeys.deleteConfirm));
    await tester.pumpAndSettle();

    expect(find.text(l10n.moduleTrajectoryDeleteFailed), findsOneWidget);
    expect(find.byKey(TrajectoryModuleKeys.delete), findsOneWidget);
  });

  testWidgets('a store that cannot be read shows the load error', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.body, ModuleId.trajectory}),
      projections: _Store(InMemoryProjectionStore(), failRead: true),
    );
    final l10n = _l10n(tester);

    await _reveal(tester, find.byKey(TrajectoryModuleKeys.stored));
    expect(_text(tester, TrajectoryModuleKeys.stored), l10n.metricLoadError);
    expect(find.text(l10n.moduleTrajectoryDataEmpty), findsNothing);
  });

  testWidgets('fits in de at 2.0 with Body off', (tester) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore(),
      locale: const Locale('de'),
      textScaler: const TextScaler.linear(2),
    );

    await _reveal(tester, find.byKey(TrajectoryModuleKeys.toggle));
    expect(tester.takeException(), isNull);
  });
}
