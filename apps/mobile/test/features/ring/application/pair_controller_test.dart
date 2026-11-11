import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/ring/application/pair_controller.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';

import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_sync_interval_store.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/protocol_lab_fakes.dart';

class _Rig {
  new({
    List<DiscoveredDevice> found = const [colmiRing, bondedRing, otherBand],
    BleTransportException? scanFailure,
    bool unreachable = false,
    bool saveFails = false,
  }) : scanner = FakeRingScanner(found: found, failure: scanFailure),
       transport = FakeBleTransport(unreachable: unreachable),
       store = RecordingPairedRingStore(fail: saveFails);

  final FakeRingScanner scanner;
  final FakeBleTransport transport;
  final permissions = FakeAppPermissions();
  final radio = FakeBluetoothRadio();
  final RecordingPairedRingStore store;
  final scheduler = FakeSyncScheduler();

  late final ProviderContainer container = ProviderContainer(
    overrides: [
      syncSchedulerProvider.overrideWithValue(scheduler),
      syncIntervalStoreProvider.overrideWithValue(
        InMemorySyncIntervalStore(SyncInterval.minutes30),
      ),
      ...protocolLabOverrides(scanner: scanner, transport: transport),
      ...onboardingOverrides(
        permissions: permissions,
        radio: radio,
        pairedStore: store,
      ),
    ],
  );

  PairController get controller => container.read(pairProvider.notifier);
  PairState get state => container.read(pairProvider);

  void keepAlive() {
    container.listen(pairProvider, (_, _) {});
    addTearDown(container.dispose);
  }
}

void main() {
  test('a scan lists only COLMI rings, strongest and bonded first', () async {
    final rig = _Rig()..keepAlive();

    await rig.controller.scan();

    expect(rig.permissions.requests, [AppPermission.bluetooth]);
    expect(rig.state.phase, PairPhase.scanning);
    expect(rig.state.scanActive, isTrue);
    expect(rig.state.devices.map((d) => d.name), ['R02_1A2B', 'R09_F800']);
    expect(rig.scanner.starts, 1);
  });

  test('a denied permission fails before any scan', () async {
    final rig = _Rig()..keepAlive();
    rig.permissions.grantOnRequest = false;

    await rig.controller.scan();

    expect(rig.state.failure, PairFailure.permissionDenied);
    expect(rig.radio.checks, 0);
    expect(rig.scanner.starts, 0);
  });

  test('a radio that stays off fails as Bluetooth off', () async {
    final rig = _Rig()..keepAlive();
    rig.radio.on = false;

    await rig.controller.scan();

    expect(rig.state.failure, PairFailure.bluetoothOff);
    expect(rig.scanner.starts, 0);
  });

  test('a scanner that cannot start fails as Bluetooth off', () async {
    final rig = _Rig(scanFailure: const BleTransportException('adapter off'))
      ..keepAlive();

    await rig.controller.scan();

    expect(rig.state.failure, PairFailure.bluetoothOff);
  });

  test('a scan that ends without a ring fails as not found', () async {
    final rig = _Rig(found: const [otherBand])..keepAlive();

    await rig.controller.scan();
    await rig.scanner.stop();
    await pumpEventQueue();

    expect(rig.state.failure, PairFailure.notFound);
  });

  test('a scan that ends with rings keeps the list to pick from', () async {
    final rig = _Rig()..keepAlive();

    await rig.controller.scan();
    await rig.scanner.stop();
    await pumpEventQueue();

    expect(rig.state.failure, isNull);
    expect(rig.state.scanActive, isFalse);
    expect(rig.state.devices, hasLength(2));
  });

  test(
    'pairing connects, saves the ring and bumps the data revision',
    () async {
      final rig = _Rig()..keepAlive();
      await rig.controller.scan();
      final revision = rig.container.read(dataRevisionProvider);
      final link = <TransportState>[];
      rig.transport.state.listen(link.add);

      await rig.controller.pair(colmiRing);
      await pumpEventQueue();

      expect(rig.state.phase, PairPhase.paired);
      expect(rig.scanner.stops, greaterThanOrEqualTo(1));
      expect(link, [
        TransportState.connecting,
        TransportState.connected,
        TransportState.disconnected,
      ]);
      final saved = rig.store.saved.single;
      expect(saved.deviceId, colmiRing.id);
      expect(saved.name, 'R09_F800');
      expect(saved.model, 'R09');
      expect(rig.container.read(dataRevisionProvider), revision + 1);
      expect(rig.scheduler.calls, [
        (interval: SyncInterval.minutes30, existing: ExistingSchedule.keep),
      ]);
    },
  );

  test('a ring that does not answer stays in the list with a notice', () async {
    final rig = _Rig(unreachable: true)..keepAlive();
    await rig.controller.scan();

    await rig.controller.pair(colmiRing);

    expect(rig.state.phase, PairPhase.scanning);
    expect(rig.state.connectFailed, isTrue);
    expect(rig.state.target, colmiRing);
    expect(rig.store.saved, isEmpty);
  });

  test(
    'a pairing that cannot be saved stays in the list with a notice',
    () async {
      final rig = _Rig(saveFails: true)..keepAlive();
      await rig.controller.scan();
      final revision = rig.container.read(dataRevisionProvider);

      await rig.controller.pair(colmiRing);

      expect(rig.state.phase, PairPhase.scanning);
      expect(rig.state.saveFailed, isTrue);
      expect(rig.state.connectFailed, isFalse);
      expect(rig.state.target, colmiRing);
      expect(rig.container.read(dataRevisionProvider), revision);
      expect(rig.scheduler.calls, isEmpty);
    },
  );

  test('an unnamed ring is saved under its model', () {
    const device = DiscoveredDevice(id: 'x', name: ' ', rssi: -60);
    const named = DiscoveredDevice(id: 'y', name: 'COLMI R06', rssi: -60);

    expect(PairController.identityOf(device).name, 'COLMI');
    expect(PairController.identityOf(named).model, 'R06');
  });
}
