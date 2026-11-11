import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_outbox_store.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/health_sync/domain/health_write_preferences.dart';
import 'package:open_ring/features/health_sync/presentation/health_status_screen.dart';

import '../../../helpers/dead_outbox_fakes.dart';
import '../../../helpers/fake_health_writer.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/settings_fakes.dart';

FakeHealthWriter _writer({
  Set<HealthRecordKind> denied = const {},
  bool unavailable = false,
}) => FakeHealthWriter()
  ..denied.addAll(denied)
  ..unavailable = unavailable;

final _sentOutbox = OutboxSummary(
  lastSentAt: settingsNow.subtract(const Duration(minutes: 12)),
);

final _partialOutbox = OutboxSummary(
  pendingRecords: const {
    HealthRecordKind.sleep: 2,
    HealthRecordKind.workout: 1,
  },
  pendingRows: 3,
  oldestPendingAt: settingsNow.subtract(const Duration(hours: 5)),
  lastSentAt: settingsNow.subtract(const Duration(minutes: 12)),
);

final _deadOutbox = OutboxSummary(
  pendingRecords: const {HealthRecordKind.heartRate: 1200},
  pendingRows: 2,
  deadRows: 3,
  lastDeadError: 'PlatformException(ERROR, SecurityException: no write)',
  oldestPendingAt: settingsNow.subtract(const Duration(days: 3)),
  lastSentAt: settingsNow.subtract(const Duration(hours: 1)),
);

final _scenarios = <String, List<Override> Function()>{
  'granted': () => settingsOverrides(
    writer: _writer(),
    outbox: FakeOutboxSummaryReader(_sentOutbox),
  ),
  'partially denied': () => settingsOverrides(
    writer: _writer(denied: {HealthRecordKind.sleep, HealthRecordKind.workout}),
    outbox: FakeOutboxSummaryReader(_partialOutbox),
  ),
  'denied': () => settingsOverrides(
    writer: _writer(denied: writableHealthKinds),
    outbox: FakeOutboxSummaryReader(deniedOutbox),
  ),
  'with dead rows': () => settingsOverrides(
    writer: _writer(),
    outbox: FakeOutboxSummaryReader(_deadOutbox),
    health: RecordingHealthSyncController(
      seed: HealthSyncState(lastError: 'HealthWriteException: busy'),
    ),
  ),
  'with a type off': () => [
    ...settingsOverrides(
      writer: _writer(),
      outbox: FakeOutboxSummaryReader(
        OutboxSummary(disabledRecords: const {HealthRecordKind.sleep: 1200}),
      ),
    ),
    healthWritePreferencesProvider.overrideWithValue(
      InMemoryHealthWritePreferences({HealthRecordKind.sleep}),
    ),
  ],
  'unavailable': () => settingsOverrides(
    writer: _writer(unavailable: true),
    outbox: FakeOutboxSummaryReader(deniedOutbox),
  ),
};

final class _RecordingToggles implements HealthWriteToggleStore {
  final calls = <String>[];

  @override
  Future<int> disablePending(
    HealthRecordKind kind, {
    required DateTime at,
  }) async {
    calls.add('off ${kind.name}');
    return 0;
  }

  @override
  Future<int> restoreDisabled(HealthRecordKind kind) async {
    calls.add('on ${kind.name}');
    return 0;
  }
}

Future<void> _pump(WidgetTester tester, List<Override> overrides) => pumpScaled(
  tester,
  screenHost(const HealthStatusScreen()),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: overrides,
);

Future<void> _tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  for (final MapEntry(key: name, value: overrides) in _scenarios.entries) {
    group('Health status $name', () {
      for (final c in layoutMatrix()) {
        testWidgets('lays out without overflow at $c', (tester) async {
          await pumpScaled(
            tester,
            screenHost(const HealthStatusScreen()),
            textScaler: c.textScaler,
            brightness: c.brightness,
            locale: c.locale,
            overrides: overrides(),
          );

          expect(find.byKey(HealthStatusKeys.status), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          await scrollThrough(tester);
          expect(find.byType(HealthStatusScreen), findsOneWidget);
        });
      }
    });
  }

  testWidgets('each type has a switch that follows its stored state', (
    tester,
  ) async {
    await _pump(tester, _scenarios['with a type off']!());

    for (final kind in writableHealthKinds) {
      await reveal(tester, find.byKey(HealthStatusKeys.toggle(kind)));
      expect(
        tester.widget<Switch>(find.byKey(HealthStatusKeys.toggle(kind))).value,
        kind != HealthRecordKind.sleep,
      );
    }
    expect(find.text('Off, 1,200 queued records held'), findsOneWidget);
  });

  testWidgets('switching a type off and on moves its queued rows', (
    tester,
  ) async {
    final toggles = _RecordingToggles();
    final preferences = InMemoryHealthWritePreferences();
    final health = RecordingHealthSyncController();
    await _pump(tester, [
      ...settingsOverrides(writer: _writer(), health: health),
      healthWritePreferencesProvider.overrideWithValue(preferences),
      healthWriteToggleStoreProvider.overrideWithValue(toggles),
    ]);
    final key = HealthStatusKeys.toggle(HealthRecordKind.heartRate);

    await _tap(tester, key);
    expect(preferences.off, {HealthRecordKind.heartRate});
    expect(toggles.calls, ['off heartRate']);
    expect(find.text('Off'), findsOneWidget);
    expect(health.processed, 0);

    await _tap(tester, key);
    expect(preferences.off, isEmpty);
    expect(toggles.calls, ['off heartRate', 'on heartRate']);
    expect(health.processed, 1);
  });

  testWidgets('granted shows connected, the empty queue and every type', (
    tester,
  ) async {
    await _pump(tester, _scenarios['granted']!());

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Your data'), findsOneWidget);
    expect(find.text('Health Connect'), findsOneWidget);
    expect(find.text('Nothing waiting'), findsOneWidget);
    expect(find.text('Last sent: 08:48'), findsOneWidget);
    expect(find.byKey(HealthStatusKeys.open), findsNothing);
    expect(find.byKey(HealthStatusKeys.fix), findsNothing);
    expect(find.byKey(HealthStatusKeys.sendNow), findsNothing);
    for (final kind in writableHealthKinds) {
      await tester.scrollUntilVisible(
        find.byKey(HealthStatusKeys.kind(kind)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    expect(find.text('Allowed'), findsNWidgets(writableHealthKinds.length));
    expect(find.text('Not allowed'), findsNothing);
  });

  testWidgets('partially denied marks the denied types and can send', (
    tester,
  ) async {
    final health = RecordingHealthSyncController();
    await _pump(
      tester,
      settingsOverrides(
        writer: _writer(
          denied: {HealthRecordKind.sleep, HealthRecordKind.workout},
        ),
        outbox: FakeOutboxSummaryReader(_partialOutbox),
        health: health,
      ),
    );

    expect(find.text('Partly allowed'), findsOneWidget);
    expect(find.text('3 records waiting'), findsOneWidget);
    await _tap(tester, HealthStatusKeys.sendNow);
    expect(health.processed, 1);

    await tester.scrollUntilVisible(
      find.byKey(HealthStatusKeys.kind(HealthRecordKind.workout)),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byKey(HealthStatusKeys.kind(HealthRecordKind.sleep)),
        matching: find.text('Not allowed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(HealthStatusKeys.kind(HealthRecordKind.heartRate)),
        matching: find.text('Allowed'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('denied lists the queue per type and opens Health Connect', (
    tester,
  ) async {
    final opener = FakeHealthSettingsOpener();
    final health = RecordingHealthSyncController();
    await _pump(
      tester,
      settingsOverrides(
        writer: _writer(denied: writableHealthKinds),
        outbox: FakeOutboxSummaryReader(deniedOutbox),
        opener: opener,
        health: health,
      ),
    );

    expect(find.text('No permission'), findsOneWidget);
    expect(find.text('310 records waiting'), findsOneWidget);
    expect(find.text('241'), findsOneWidget);
    expect(find.text('Oldest in the queue: 08:12'), findsOneWidget);

    await _tap(tester, HealthStatusKeys.open);
    expect(opener.opened, 1);

    await _tap(tester, HealthStatusKeys.askAgain);
    expect(health.requested, 1);
    expect(health.processed, 1);

    await tester.scrollUntilVisible(
      find.byKey(HealthStatusKeys.fix),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Tap Open Health Connect below.'), findsOneWidget);
  });

  testWidgets('dead rows and a failed run are explained', (tester) async {
    await _pump(tester, _scenarios['with dead rows']!());

    expect(find.byKey(HealthStatusKeys.error), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(HealthStatusKeys.dead),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('3 batches failed 8 times and are no longer sent'),
      findsOneWidget,
    );
    expect(
      find.text('Last error: Health Connect did not allow the write.'),
      findsOneWidget,
    );
    expect(find.byKey(HealthStatusKeys.retryDead), findsOneWidget);
  });

  testWidgets('Try again resets the dead rows and sends the queue', (
    tester,
  ) async {
    final health = RecordingHealthSyncController();
    final store = FakeDeadOutboxStore({
      HealthRecordKind.heartRate: 'HealthWriteException: write failed',
      HealthRecordKind.sleep: 'busy',
    });
    final outbox = FakeOutboxSummaryReader(
      OutboxSummary(
        deadRows: 2,
        lastDeadError: 'HealthWriteException: write failed',
      ),
    );
    await _pump(tester, [
      ...settingsOverrides(writer: _writer(), outbox: outbox, health: health),
      deadOutboxStoreProvider.overrideWithValue(store),
    ]);

    expect(
      find.text('Last error: Health Connect did not accept the data.'),
      findsOneWidget,
    );
    outbox.value = OutboxSummary(pendingRows: 2);
    await _tap(tester, HealthStatusKeys.retryDead);

    expect(store.resets, [null]);
    expect(store.dead, isEmpty);
    expect(health.processed, 1);
    expect(find.byKey(HealthStatusKeys.dead), findsNothing);
    expect(find.byKey(HealthStatusKeys.retryDead), findsNothing);
  });

  testWidgets('while sending, Try again waits', (tester) async {
    await _pump(
      tester,
      settingsOverrides(
        writer: _writer(),
        outbox: FakeOutboxSummaryReader(_deadOutbox),
        health: RecordingHealthSyncController(
          seed: HealthSyncState(running: true),
        ),
      ),
    );
    await reveal(tester, find.byKey(HealthStatusKeys.retryDead));

    final button = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(HealthStatusKeys.retryDead),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byKey(HealthStatusKeys.retryDead),
        matching: find.text('Sending…'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('without dead rows there is nothing to try again', (
    tester,
  ) async {
    await _pump(tester, _scenarios['partially denied']!());

    expect(find.byKey(HealthStatusKeys.dead), findsNothing);
    expect(find.byKey(HealthStatusKeys.retryDead), findsNothing);
  });

  testWidgets('explains dead rows in German', (tester) async {
    await pumpScaled(
      tester,
      screenHost(const HealthStatusScreen()),
      textScaler: const TextScaler.linear(2),
      brightness: Brightness.light,
      locale: const Locale('de'),
      overrides: _scenarios['with dead rows']!(),
    );
    await reveal(tester, find.byKey(HealthStatusKeys.retryDead));

    expect(
      find.text(
        'Letzter Fehler: Health Connect hat das Schreiben nicht erlaubt.',
      ),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('the open button comes after the steps that name it', (
    tester,
  ) async {
    await _pump(tester, _scenarios['denied']!());

    expect(find.text('Your data'), findsNothing);
    await reveal(tester, find.byKey(HealthStatusKeys.open));
    expect(
      tester.getTopLeft(find.byKey(HealthStatusKeys.open)).dy,
      greaterThan(
        tester.getTopLeft(find.text('Tap Open Health Connect below.')).dy,
      ),
    );
  });

  testWidgets('types keep the prototype order and say what is written', (
    tester,
  ) async {
    await _pump(tester, _scenarios['granted']!());

    final heart = find.byKey(HealthStatusKeys.kind(HealthRecordKind.heartRate));
    await reveal(tester, heart);
    expect(find.text('Every sample, not just the average'), findsOneWidget);
    final sleep = find.byKey(HealthStatusKeys.kind(HealthRecordKind.sleep));
    expect(
      tester.getTopLeft(sleep).dy,
      greaterThan(tester.getTopLeft(heart).dy),
    );
  });

  testWidgets('unavailable offers to open Health Connect, not to ask again', (
    tester,
  ) async {
    await _pump(tester, _scenarios['unavailable']!());

    expect(find.text('Not available'), findsOneWidget);
    expect(find.byKey(HealthStatusKeys.open), findsOneWidget);
    expect(find.byKey(HealthStatusKeys.askAgain), findsNothing);
    expect(find.byKey(HealthStatusKeys.sendNow), findsNothing);
  });

  testWidgets('reads the denied state in German', (tester) async {
    await pumpScaled(
      tester,
      screenHost(const HealthStatusScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.light,
      locale: const Locale('de'),
      overrides: _scenarios['denied']!(),
    );

    expect(find.text('Keine Berechtigung'), findsOneWidget);
    expect(find.text('310 Einträge warten'), findsOneWidget);
    expect(find.text('Health Connect öffnen'), findsOneWidget);
  });
}
