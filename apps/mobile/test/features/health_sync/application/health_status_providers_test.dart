import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

import '../../../helpers/fake_health_writer.dart';
import '../../../helpers/settings_fakes.dart';

HealthStatusView _view(Map<HealthRecordKind, HealthAccess> access) =>
    HealthStatusView(access: access, outbox: OutboxSummary());

void main() {
  group('connection', () {
    test('a disabled type does not count against the connection', () {
      expect(
        HealthStatusView(
          access: const {
            HealthRecordKind.sleep: HealthAccess.denied,
            HealthRecordKind.heartRate: HealthAccess.granted,
          },
          outbox: OutboxSummary(),
          disabled: const {HealthRecordKind.sleep},
        ).connection,
        HealthConnection.connected,
      );
    });

    test('with every type disabled the real access still shows', () {
      expect(
        HealthStatusView(
          access: const {HealthRecordKind.sleep: HealthAccess.denied},
          outbox: OutboxSummary(),
          disabled: const {HealthRecordKind.sleep},
        ).connection,
        HealthConnection.denied,
      );
    });

    test('every kind granted is connected', () {
      expect(
        _view({
          HealthRecordKind.sleep: HealthAccess.granted,
          HealthRecordKind.heartRate: HealthAccess.granted,
        }).connection,
        HealthConnection.connected,
      );
    });

    test('some kinds denied is partial', () {
      expect(
        _view({
          HealthRecordKind.sleep: HealthAccess.denied,
          HealthRecordKind.heartRate: HealthAccess.granted,
        }).connection,
        HealthConnection.partial,
      );
    });

    test('every kind denied is denied', () {
      expect(
        _view({
          HealthRecordKind.sleep: HealthAccess.denied,
          HealthRecordKind.heartRate: HealthAccess.denied,
        }).connection,
        HealthConnection.denied,
      );
    });

    test('a missing platform wins over any grant', () {
      expect(
        _view({
          HealthRecordKind.sleep: HealthAccess.unavailable,
          HealthRecordKind.heartRate: HealthAccess.granted,
        }).connection,
        HealthConnection.unavailable,
      );
    });
  });

  test('the status asks the writer about every writable kind', () async {
    final writer = FakeHealthWriter()..denied.add(HealthRecordKind.hrv);
    final container = ProviderContainer(
      overrides: settingsOverrides(
        writer: writer,
        outbox: FakeOutboxSummaryReader(deniedOutbox),
      ),
    );
    addTearDown(container.dispose);

    final view = await container.read(healthStatusProvider.future);

    expect(view.access.keys.toSet(), writableHealthKinds);
    expect(view.access[HealthRecordKind.hrv], HealthAccess.denied);
    expect(view.access.containsKey(HealthRecordKind.stress), isFalse);
    expect(view.outbox.pendingRecordCount, 310);
    expect(view.connection, HealthConnection.partial);
  });
}
