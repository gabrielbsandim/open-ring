import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/application/auto_measurements_controller.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/ring_fakes.dart';

void main() {
  test('reads the paired ring choice and saves a change', () async {
    final store = FakeSyncStore(ring: const PairedRing(deviceId: fakeRingId));
    final container = ProviderContainer.test(
      overrides: ringOverrides(store: store),
    );

    expect(
      await container.read(autoMeasurementsProvider.future),
      AutoMeasurements.allOn,
    );

    await container
        .read(autoMeasurementsProvider.notifier)
        .turn(AutoMeasurement.hrv, on: false);

    const expected = AutoMeasurements(off: {AutoMeasurement.hrv});
    expect(container.read(autoMeasurementsProvider).value, expected);
    expect(store.ring?.measurements, expected);
  });

  test('without a paired ring there is no choice to show', () async {
    final container = ProviderContainer.test(overrides: ringOverrides());

    expect(await container.read(autoMeasurementsProvider.future), isNull);
  });

  test('turning one back on keeps the others off', () {
    const off = AutoMeasurements(
      off: {AutoMeasurement.spo2, AutoMeasurement.stress},
    );

    expect(
      off.turned(AutoMeasurement.spo2, on: true),
      const AutoMeasurements(off: {AutoMeasurement.stress}),
    );
    expect(off.isOn(AutoMeasurement.heartRate), isTrue);
  });
}
