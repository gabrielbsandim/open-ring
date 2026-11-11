import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/application/retry_dead_health_rows.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

import '../../../helpers/dead_outbox_fakes.dart';
import '../../../helpers/fake_health_writer.dart';
import '../../../helpers/settings_fakes.dart';

const _permission = 'PlatformException(ERROR, SecurityException: denied)';

void main() {
  group('Try again', () {
    test('resets every dead row, then processes the outbox', () async {
      final store = FakeDeadOutboxStore({
        HealthRecordKind.heartRate: 'busy',
        HealthRecordKind.sleep: _permission,
      });
      var processed = 0;
      final retry = RetryDeadHealthRows(
        outbox: store,
        process: () async => processed++,
      );

      expect(await retry(), 2);

      expect(store.resets, [null]);
      expect(store.dead, isEmpty);
      expect(processed, 1);
    });

    test('can reset one kind only', () async {
      final store = FakeDeadOutboxStore({
        HealthRecordKind.heartRate: 'busy',
        HealthRecordKind.sleep: 'busy',
      });
      var processed = 0;
      final retry = RetryDeadHealthRows(
        outbox: store,
        process: () async => processed++,
      );

      expect(await retry(kind: HealthRecordKind.sleep), 1);

      expect(store.dead.keys, [HealthRecordKind.heartRate]);
      expect(processed, 1);
    });

    test('with nothing dead it does not process', () async {
      var processed = 0;
      final retry = RetryDeadHealthRows(
        outbox: FakeDeadOutboxStore(),
        process: () async => processed++,
      );

      expect(await retry(), 0);
      expect(processed, 0);
    });
  });

  group('after a grant', () {
    test('resets only the kinds a missing permission killed', () async {
      final store = FakeDeadOutboxStore({
        HealthRecordKind.heartRate: _permission,
        HealthRecordKind.workout: 'Exception: missing permission for route',
        HealthRecordKind.sleep: 'HealthWriteException: write failed',
        HealthRecordKind.spo2: null,
      });
      var processed = 0;
      final retry = RetryDeadHealthRows(
        outbox: store,
        process: () async => processed++,
      );

      expect(await retry.afterGrant(), 2);

      expect(
        store.resets,
        unorderedEquals([HealthRecordKind.heartRate, HealthRecordKind.workout]),
      );
      expect(
        store.dead.keys,
        unorderedEquals([HealthRecordKind.sleep, HealthRecordKind.spo2]),
      );
      expect(processed, 1);
    });

    test('with no permission failure it leaves everything alone', () async {
      final store = FakeDeadOutboxStore({HealthRecordKind.sleep: 'busy'});
      var processed = 0;
      final retry = RetryDeadHealthRows(
        outbox: store,
        process: () async => processed++,
      );

      expect(await retry.afterGrant(), 0);
      expect(store.resets, isEmpty);
      expect(processed, 0);
    });
  });

  group('grant watch', () {
    const granted = HealthAccess.granted;
    const denied = HealthAccess.denied;

    test('the first look only sets the baseline', () {
      final watch = HealthGrantWatch();

      expect(watch.observe({HealthRecordKind.sleep: granted}), isFalse);
    });

    test('fires when a missing kind becomes granted, once', () {
      final watch = HealthGrantWatch()
        ..observe({
          HealthRecordKind.sleep: denied,
          HealthRecordKind.heartRate: granted,
        });

      expect(
        watch.observe({
          HealthRecordKind.sleep: denied,
          HealthRecordKind.heartRate: granted,
        }),
        isFalse,
      );
      expect(
        watch.observe({
          HealthRecordKind.sleep: granted,
          HealthRecordKind.heartRate: granted,
        }),
        isTrue,
      );
      expect(
        watch.observe({
          HealthRecordKind.sleep: granted,
          HealthRecordKind.heartRate: granted,
        }),
        isFalse,
      );
    });

    test('a newly installed platform counts as a grant', () {
      final watch = HealthGrantWatch()
        ..observe({HealthRecordKind.sleep: HealthAccess.unavailable});

      expect(watch.observe({HealthRecordKind.sleep: granted}), isTrue);
    });

    test('losing a permission does not fire', () {
      final watch = HealthGrantWatch()
        ..observe({HealthRecordKind.sleep: granted});

      expect(watch.observe({HealthRecordKind.sleep: denied}), isFalse);
    });
  });

  group('failure kinds', () {
    test('read the stored error in plain categories', () {
      expect(OutboxFailure.of(_permission), OutboxFailure.permission);
      expect(
        OutboxFailure.of('MissingPluginException(No implementation)'),
        OutboxFailure.unavailable,
      );
      expect(
        OutboxFailure.of('TimeoutException after 0:00:30'),
        OutboxFailure.unavailable,
      );
      expect(
        OutboxFailure.of('HealthWriteException: write HEART_RATE x failed'),
        OutboxFailure.rejected,
      );
      expect(OutboxFailure.of('StateError: bad'), OutboxFailure.unknown);
      expect(OutboxFailure.of(null), OutboxFailure.unknown);
    });
  });

  test(
    'permission granted while the app runs resets dead rows by itself',
    () async {
      final writer = FakeHealthWriter()..denied.addAll(writableHealthKinds);
      final store = FakeDeadOutboxStore({
        HealthRecordKind.heartRate: _permission,
      });
      var processed = 0;
      final container = ProviderContainer.test(
        overrides: [
          ...settingsOverrides(writer: writer),
          retryDeadHealthRowsProvider.overrideWithValue(
            RetryDeadHealthRows(
              outbox: store,
              process: () async => processed++,
            ),
          ),
        ],
      )..listen(healthGrantRetryProvider, (_, _) {});
      await container.read(healthAccessProvider.future);

      writer.denied.clear();
      container.invalidate(healthAccessProvider);
      await container.read(healthAccessProvider.future);
      await pumpEventQueue();

      expect(store.resets, [HealthRecordKind.heartRate]);
      expect(store.dead, isEmpty);
      expect(processed, 1);
    },
  );
}
