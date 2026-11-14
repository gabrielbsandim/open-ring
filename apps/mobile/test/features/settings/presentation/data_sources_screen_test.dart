import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/settings/presentation/data_sources_screen.dart';

import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/ring_fakes.dart' show ringOverrides;
import '../../../helpers/settings_fakes.dart';

const _watch = 'com.garmin.android.apps.connectmobile';
const _band = 'com.mi.health';

final _lastNight = DateTime.utc(2026, 11, 9, 23);
final _lastRun = DateTime.utc(2026, 11, 9, 18);

typedef _Reads = ({
  FakeHealthReader reader,
  InMemoryHealthReadStore store,
  FakeHealthSettingsOpener opener,
});

Future<_Reads> _reads({
  bool enabled = false,
  HealthAccess access = HealthAccess.denied,
  List<String> sources = const [],
  bool workoutsEnabled = false,
  List<String> workoutSources = const [],
}) async {
  final store = InMemoryHealthReadStore();
  await store.saveSleep([
    for (final (index, source) in sources.indexed)
      externalNight(source, _lastNight.subtract(Duration(days: index))),
  ], readAt: metricsNow);
  await store.saveWorkouts([
    for (final (index, source) in workoutSources.indexed)
      externalWorkout(source, _lastRun.subtract(Duration(hours: index))),
  ], readAt: metricsNow);
  await store.setEnabled(HealthRecordKind.sleep, enabled: enabled);
  await store.setEnabled(HealthRecordKind.workout, enabled: workoutsEnabled);
  return (
    reader: FakeHealthReader(
      access: access,
      nights: [externalNight(_watch, _lastNight)],
      sessions: [externalWorkout(_watch, _lastRun)],
    ),
    store: store,
    opener: FakeHealthSettingsOpener(),
  );
}

List<Override> _overrides(
  MetricsScenario scenario,
  _Reads reads, {
  List<Override> ring = const [],
}) => [
  ...metricsOverrides(scenario, ring: ring),
  healthReaderProvider.overrideWithValue(reads.reader),
  healthReadStoreProvider.overrideWithValue(reads.store),
  healthSettingsOpenerProvider.overrideWithValue(reads.opener),
];

final _states = <String, Future<_Reads> Function()>{
  'reading off': _reads,
  'reading unavailable': () => _reads(access: HealthAccess.unavailable),
  'two other apps first in line': () => _reads(
    enabled: true,
    access: HealthAccess.granted,
    sources: const [_watch, _band],
  ),
  'access removed': () => _reads(enabled: true, sources: const [_watch]),
  'workouts from two apps': () => _reads(
    enabled: true,
    access: HealthAccess.granted,
    sources: const [_watch],
    workoutsEnabled: true,
    workoutSources: const [_watch, _band],
  ),
};

final _scenarios = <String, MetricsScenario>{
  'with a paired ring': fullDataScenario,
  'without a ring': noDataScenario,
};

Future<void> _pump(
  WidgetTester tester,
  _Reads reads, {
  MetricsScenario? scenario,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
  FakeSyncScheduler? scheduler,
}) => pumpScaled(
  tester,
  screenHost(const DataSourcesScreen()),
  textScaler: TextScaler.noScaling,
  brightness: brightness,
  locale: locale,
  overrides: _overrides(
    scenario ?? fullDataScenario,
    reads,
    ring: scheduler == null
        ? const []
        : ringOverrides(
            paired: (scenario ?? fullDataScenario).pairedRing,
            scheduler: scheduler,
            clock: () => metricsNow,
          ),
  ),
);

List<String> _shownOrder(
  WidgetTester tester, {
  HealthRecordKind kind = HealthRecordKind.sleep,
}) {
  final prefix = kind == HealthRecordKind.sleep
      ? 'sources_drag_'
      : 'sources_drag_${kind.name}_';
  final handles = find.descendant(
    of: find.byKey(DataSourcesKeys.priorityOf(kind)),
    matching: find.byType(ReorderableDragStartListener),
  );
  return [
    for (final element in handles.evaluate())
      (element.widget.key! as ValueKey<String>).value.replaceFirst(prefix, ''),
  ];
}

void main() {
  for (final MapEntry(key: name, value: scenario) in _scenarios.entries) {
    for (final MapEntry(key: state, value: reads) in _states.entries) {
      group('Data sources $name, $state', () {
        for (final c in layoutMatrix()) {
          testWidgets('lays out without overflow at $c', (tester) async {
            await pumpScaled(
              tester,
              screenHost(const DataSourcesScreen()),
              textScaler: c.textScaler,
              brightness: c.brightness,
              locale: c.locale,
              overrides: _overrides(scenario, await reads()),
            );

            expect(find.byType(CircularProgressIndicator), findsNothing);
            await scrollThrough(tester);
            expect(find.byType(DataSourcesScreen), findsOneWidget);
          });
        }
      });
    }
  }

  testWidgets('shows only the choices, no metric list or diagnostics', (
    tester,
  ) async {
    await _pump(tester, await _reads());

    expect(find.byKey(DataSourcesKeys.readSleep), findsOneWidget);
    expect(find.byKey(DataSourcesKeys.readWorkouts), findsOneWidget);
    await scrollThrough(tester);
    expect(find.text('Main'), findsNothing);
    expect(find.text('Computed here'), findsNothing);
    expect(find.text('Where each metric comes from'), findsNothing);
    expect(find.text('Two fixed rules'), findsNothing);
    expect(find.text('Priority'), findsNothing);
  });

  testWidgets('workout reading starts off with no order to choose', (
    tester,
  ) async {
    await _pump(tester, await _reads());

    final toggle = find.byKey(DataSourcesKeys.readWorkouts);
    await reveal(tester, toggle);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.textContaining('read access to workouts only'), findsOneWidget);
    expect(find.byKey(DataSourcesKeys.workoutPriority), findsNothing);
  });

  testWidgets('turning workouts on asks for workout access only', (
    tester,
  ) async {
    final reads = await _reads();
    await _pump(tester, reads);

    await reveal(tester, find.byKey(DataSourcesKeys.readWorkouts));
    await tester.tap(find.byKey(DataSourcesKeys.readWorkouts));
    await tester.pumpAndSettle();

    expect(reads.reader.requests, [HealthRecordKind.workout]);
    expect(
      (await reads.store.settings(HealthRecordKind.workout)).enabled,
      isTrue,
    );
    expect(
      (await reads.store.settings(HealthRecordKind.sleep)).enabled,
      isFalse,
    );
    await reveal(tester, find.byKey(DataSourcesKeys.workoutPriority));
    expect(_shownOrder(tester, kind: HealthRecordKind.workout), [
      ringSource,
      _watch,
    ]);
    expect(find.text('OpenRing'), findsOneWidget);
  });

  testWidgets('apps are named in the order, without record counts', (
    tester,
  ) async {
    await _pump(tester, await _states['workouts from two apps']!());
    await scrollThrough(tester);

    expect(find.text('Garmin Connect'), findsWidgets);
    expect(find.textContaining('1 night'), findsNothing);
    expect(find.textContaining('last data'), findsNothing);
  });

  testWidgets('workout move buttons reorder only the workout order', (
    tester,
  ) async {
    final reads = await _states['workouts from two apps']!();
    await _pump(tester, reads);
    const kind = HealthRecordKind.workout;
    await reveal(tester, find.byKey(DataSourcesKeys.workoutPriority));

    expect(find.textContaining('When two workouts overlap'), findsOneWidget);
    await tester.tap(find.byKey(DataSourcesKeys.moveUp(_band, kind: kind)));
    await tester.pumpAndSettle();

    expect(_shownOrder(tester, kind: kind), [ringSource, _band, _watch]);
    expect(await reads.store.storedPriority(kind), [ringSource, _band, _watch]);
    expect(await reads.store.storedPriority(HealthRecordKind.sleep), [
      ringSource,
      _watch,
    ]);
  });

  testWidgets('sleep reading starts off with no order to choose', (
    tester,
  ) async {
    await _pump(tester, await _reads());

    await reveal(tester, find.byKey(DataSourcesKeys.readSleep));
    expect(
      tester.widget<Switch>(find.byKey(DataSourcesKeys.readSleep)).value,
      isFalse,
    );
    expect(find.textContaining('read access to sleep only'), findsOneWidget);
    expect(find.byKey(DataSourcesKeys.priority), findsNothing);
  });

  testWidgets('turning sleep on asks for sleep read access and lists the app', (
    tester,
  ) async {
    final reads = await _reads();
    await _pump(tester, reads);

    await reveal(tester, find.byKey(DataSourcesKeys.readSleep));
    await tester.tap(find.byKey(DataSourcesKeys.readSleep));
    await tester.pumpAndSettle();

    expect(reads.reader.requests, [HealthRecordKind.sleep]);
    expect(
      (await reads.store.settings(HealthRecordKind.sleep)).enabled,
      isTrue,
    );
    await reveal(tester, find.byKey(DataSourcesKeys.priority));
    expect(_shownOrder(tester), [ringSource, _watch]);
    expect(find.text('Garmin Connect'), findsOneWidget);
  });

  testWidgets('a declined request offers to open Health Connect', (
    tester,
  ) async {
    final reads = await _reads();
    reads.reader.grantOnRequest = false;
    await _pump(tester, reads);

    await reveal(tester, find.byKey(DataSourcesKeys.readSleep));
    await tester.tap(find.byKey(DataSourcesKeys.readSleep));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(DataSourcesKeys.openHealth));
    await tester.tap(find.byKey(DataSourcesKeys.openHealth));
    await tester.pumpAndSettle();

    expect(reads.opener.opened, 1);
    expect(
      tester.widget<Switch>(find.byKey(DataSourcesKeys.readSleep)).value,
      isFalse,
    );
  });

  testWidgets('move buttons reorder the sleep sources and save the order', (
    tester,
  ) async {
    final reads = await _reads(
      enabled: true,
      access: HealthAccess.granted,
      sources: const [_watch, _band],
    );
    await _pump(tester, reads);
    await reveal(tester, find.byKey(DataSourcesKeys.priority));

    expect(
      tester
          .widget<IconButton>(find.byKey(DataSourcesKeys.moveUp(ringSource)))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(DataSourcesKeys.moveDown(_band)))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(DataSourcesKeys.moveDown(ringSource)));
    await tester.pumpAndSettle();

    expect(_shownOrder(tester), [_watch, ringSource, _band]);
    expect(await reads.store.storedPriority(HealthRecordKind.sleep), [
      _watch,
      ringSource,
      _band,
    ]);
    expect(find.byTooltip('Move Garmin Connect up'), findsOneWidget);
  });

  testWidgets('dragging a handle moves the source', (tester) async {
    final reads = await _reads(
      enabled: true,
      access: HealthAccess.granted,
      sources: const [_watch, _band],
    );
    await _pump(tester, reads);
    await reveal(tester, find.byKey(DataSourcesKeys.drag(_band)));

    final handle = find.byKey(DataSourcesKeys.drag(_band));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    final rowHeight = tester.getSize(find.byKey(DataSourcesKeys.rank(_band)));
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(Offset(0, -rowHeight.height / 4));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_shownOrder(tester).first, _band);
    expect(
      (await reads.store.storedPriority(HealthRecordKind.sleep)).first,
      _band,
    );
  });

  testWidgets('without a ring the switches are still there', (tester) async {
    await _pump(
      tester,
      await _reads(),
      scenario: noDataScenario,
      locale: const Locale('de'),
      brightness: Brightness.light,
    );

    expect(find.text('Schlaf aus anderen Apps'), findsOneWidget);
    expect(find.byKey(DataSourcesKeys.readWorkouts), findsOneWidget);
  });

  testWidgets('criterion 6: turning a read on asks for background access', (
    tester,
  ) async {
    final reads = await _reads();
    final scheduler = FakeSyncScheduler();
    await _pump(tester, reads, scenario: noDataScenario, scheduler: scheduler);

    await reveal(tester, find.byKey(DataSourcesKeys.readSleep));
    await tester.tap(find.byKey(DataSourcesKeys.readSleep));
    await tester.pumpAndSettle();

    expect(reads.reader.backgroundRequests, 1);
    expect(scheduler.calls, hasLength(1));
  });

  testWidgets('criterion 6: turning the last read off re-evaluates the job', (
    tester,
  ) async {
    final reads = await _reads(
      enabled: true,
      access: HealthAccess.granted,
      sources: const [_watch],
    );
    reads.reader.backgroundAllowed = true;
    final scheduler = FakeSyncScheduler();
    await _pump(tester, reads, scenario: noDataScenario, scheduler: scheduler);

    await reveal(tester, find.byKey(DataSourcesKeys.readSleep));
    await tester.tap(find.byKey(DataSourcesKeys.readSleep));
    await tester.pumpAndSettle();

    expect(reads.reader.backgroundRequests, 0);
    expect(scheduler.cancels, 1);
    expect(scheduler.calls, isEmpty);
  });
}
