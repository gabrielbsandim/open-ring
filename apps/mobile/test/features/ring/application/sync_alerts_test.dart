import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/domain/ring_alerts.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/ring_fakes.dart';

const _ring = 'ring-1';
final _now = DateTime.utc(2026, 11, 10, 9);
final AppLocalizations _strings = lookupAppLocalizations(const Locale('en'));

final class _Rig {
  new({
    bool allowed = true,
    Set<RingAlert>? enabled,
    String? warned,
    List<SyncRun>? runs,
    PairedRing? ring = const PairedRing(deviceId: _ring),
  }) : notifier = InMemoryRingNotifier(allowed: allowed),
       preferences = InMemoryRingAlertPreferences(
         enabled: enabled,
         warned: warned,
       ),
       store = FakeSyncStore(ring: ring, runs: runs);

  final InMemoryRingNotifier notifier;
  final InMemoryRingAlertPreferences preferences;
  final FakeSyncStore store;

  SyncAlerts get alerts => SyncAlerts(
    store: store,
    preferences: preferences,
    notifier: notifier,
    strings: _strings,
  );

  Future<void> battery(int percent, {bool charging = false}) =>
      alerts.afterSync(
        SyncCompleted(
          SyncReport(
            syncedAt: _now,
            written: const {},
            failures: const {},
            battery: BatteryStatus(percent: percent, charging: charging),
          ),
        ),
      );

  Future<void> fail() async {
    store.runs.insert(0, _failed);
    await alerts.afterSync(
      SyncFailed(
        SyncAbortedException(SyncStep.connecting, Exception('out of range')),
      ),
    );
  }

  Future<void> succeed() async {
    store.runs.insert(0, _completed);
    await alerts.afterSync(
      SyncCompleted(
        SyncReport(syncedAt: _now, written: const {}, failures: const {}),
      ),
    );
  }

  int get shown => notifier.shown.length;
}

final _failed = SyncRun(at: _now, outcome: SyncRunOutcome.unreachable);
final _completed = SyncRun(at: _now, outcome: SyncRunOutcome.completed);

void main() {
  group('low battery', () {
    test('alerts once at the threshold, with the percentage', () async {
      final rig = _Rig();

      await rig.battery(lowBatteryPercent);

      expect(rig.shown, 1);
      expect(
        rig.notifier.shown.single.title,
        _strings.ringAlertLowBatteryTitle,
      );
      expect(rig.notifier.shown.single.body, contains('20%'));
      expect(rig.preferences.warned, _ring);
    });

    test('above the threshold stays quiet', () async {
      final rig = _Rig();

      await rig.battery(lowBatteryPercent + 1);

      expect(rig.shown, 0);
    });

    test('the same episode alerts only once as the level drops', () async {
      final rig = _Rig();

      await rig.battery(20);
      await rig.battery(15);
      await rig.battery(5);

      expect(rig.shown, 1);
    });

    test(
      'hovering between the threshold and the re-arm level stays quiet',
      () async {
        final rig = _Rig();

        await rig.battery(20);
        await rig.battery(29);
        await rig.battery(19);

        expect(rig.shown, 1);
      },
    );

    test('a reading at the re-arm level starts a new episode', () async {
      final rig = _Rig();

      await rig.battery(20);
      await rig.battery(batteryRearmPercent);
      expect(rig.preferences.warned, isNull);
      await rig.battery(20);

      expect(rig.shown, 2);
    });

    test('a charging ring is not alerted', () async {
      final rig = _Rig();

      await rig.battery(10, charging: true);

      expect(rig.shown, 0);
      expect(rig.preferences.warned, isNull);
    });

    test('a different ring has its own episode', () async {
      final rig = _Rig(warned: 'other-ring');

      await rig.battery(10);

      expect(rig.shown, 1);
      expect(rig.preferences.warned, _ring);
    });

    test('the toggle off sends nothing and does not use the episode', () async {
      final rig = _Rig(enabled: {RingAlert.syncFailed});

      await rig.battery(10);

      expect(rig.shown, 0);
      expect(rig.preferences.warned, isNull);
    });

    test('a denied permission does not use the episode', () async {
      final rig = _Rig(allowed: false);

      await rig.battery(10);
      expect(rig.shown, 0);
      expect(rig.preferences.warned, isNull);

      rig.notifier.allowed = true;
      await rig.battery(10);
      expect(rig.shown, 1);
    });

    test('a sync with no battery reading changes nothing', () async {
      final rig = _Rig(warned: _ring);

      await rig.succeed();

      expect(rig.shown, 0);
      expect(rig.preferences.warned, _ring);
    });

    test('a show that throws leaves the episode unused', () async {
      final rig = _Rig();
      final throwing = SyncAlerts(
        store: rig.store,
        preferences: rig.preferences,
        notifier: _ThrowingNotifier(),
        strings: _strings,
      );

      await expectLater(
        throwing.afterSync(
          SyncCompleted(
            SyncReport(
              syncedAt: _now,
              written: const {},
              failures: const {},
              battery: const BatteryStatus(percent: 10, charging: false),
            ),
          ),
        ),
        throwsStateError,
      );
      expect(rig.preferences.warned, isNull);
    });
  });

  group('sync failed', () {
    test('the first two failures are silent, the third alerts', () async {
      final rig = _Rig();

      await rig.fail();
      await rig.fail();
      expect(rig.shown, 0);

      await rig.fail();
      expect(rig.shown, 1);
      expect(
        rig.notifier.shown.single.title,
        _strings.ringAlertSyncFailedTitle,
      );
      expect(rig.notifier.shown.single.body, contains('3'));
    });

    test('every failure after the third stays silent', () async {
      final rig = _Rig();

      for (var i = 0; i < 10; i++) {
        await rig.fail();
      }

      expect(rig.shown, 1);
    });

    test('a success resets the streak', () async {
      final rig = _Rig();

      await rig.fail();
      await rig.fail();
      await rig.succeed();
      await rig.fail();
      await rig.fail();
      expect(rig.shown, 0);

      await rig.fail();
      expect(rig.shown, 1);
    });

    test('a new streak after a success alerts again', () async {
      final rig = _Rig();

      for (var i = 0; i < 4; i++) {
        await rig.fail();
      }
      await rig.succeed();
      for (var i = 0; i < 3; i++) {
        await rig.fail();
      }

      expect(rig.shown, 2);
    });

    test('a ring out of range counts, it is logged as unreachable', () {
      expect(
        SyncPairedRing.failedRun(
          SyncAbortedException(SyncStep.connecting, Exception('out of range')),
          at: _now,
        ).failed,
        isTrue,
      );
    });

    test('the toggle off sends nothing', () async {
      final rig = _Rig(enabled: {RingAlert.lowBattery});

      for (var i = 0; i < 3; i++) {
        await rig.fail();
      }

      expect(rig.shown, 0);
    });

    test('a denied permission sends nothing', () async {
      final rig = _Rig(allowed: false);

      for (var i = 0; i < 3; i++) {
        await rig.fail();
      }

      expect(rig.shown, 0);
    });
  });

  test('no paired ring sends nothing', () async {
    final rig = _Rig(ring: null, runs: [_failed, _failed, _failed]);

    await rig.alerts.afterSync(
      SyncFailed(SyncAbortedException(SyncStep.connecting, Exception('x'))),
    );

    expect(rig.shown, 0);
  });

  test('a skipped run sends nothing', () async {
    final rig = _Rig(runs: [_failed, _failed, _failed]);

    await rig.alerts.afterSync(const AlreadySyncing());
    await rig.alerts.afterSync(const NothingPaired());

    expect(rig.shown, 0);
  });

  group('alert language', () {
    test('a supported system language is used', () {
      expect(
        ringAlertStrings(const [Locale('ja')]).localeName,
        lookupAppLocalizations(const Locale('ja')).localeName,
      );
    });

    test('an unsupported system language falls back to English', () {
      expect(ringAlertStrings(const [Locale('ko', 'KR')]).localeName, 'en');
    });
  });
}

final class _ThrowingNotifier implements RingNotifier {
  @override
  Future<bool> enabled() async => true;

  @override
  Future<void> show(RingNotification notification) async =>
      throw StateError('notifications down');
}
