import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/presentation/sync_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations_en.dart';
import 'package:ring_driver/ring_driver.dart';

void main() {
  final l10n = AppLocalizationsEn();

  final order = [
    const SyncProgress(SyncStep.connecting),
    const SyncProgress(SyncStep.settingTime),
    const SyncProgress(SyncStep.readingBattery),
    for (final kind in RecordKind.values)
      SyncProgress(SyncStep.pulling, kind: kind),
    const SyncProgress(SyncStep.saving),
    const SyncProgress(SyncStep.disconnecting),
  ];

  test('progress rises step by step and ends full', () {
    final fractions = [for (final p in order) p.fraction];

    for (var i = 1; i < fractions.length; i++) {
      expect(fractions[i], greaterThan(fractions[i - 1]));
    }
    expect(fractions.first, greaterThan(0));
    expect(fractions.last, 1);
  });

  test('every step has its own label', () {
    final labels = {for (final p in order) p.label(l10n)};

    expect(labels, hasLength(order.length));
    expect(
      const SyncProgress(
        SyncStep.pulling,
        kind: RecordKind.heartRate,
      ).label(l10n),
      'Fetching heart rate',
    );
  });

  test('errors explain what happened', () {
    expect(const NoPairedRing().message(l10n), contains('Pair one'));
    expect(
      SyncErrorLabels(const SyncAborted(SyncStep.connecting, 'timeout'))
          .message(l10n),
      contains('Could not reach the ring'),
    );
    final partial = CapabilitiesFailed(const [
      RingCapability.hrv,
      RingCapability.sleep,
    ]);
    expect(partial.title(l10n), 'Sync incomplete');
    expect(partial.message(l10n), contains('HRV, sleep'));
    expect(partial.partial, isTrue);
  });
}
