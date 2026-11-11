import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';
import 'package:ring_driver/ring_driver.dart';

const _pullSteps = 3;
final int _positions = SyncStep.values.length - 1 + RecordKind.values.length;

extension SyncProgressLabels on SyncProgress {
  String label(AppLocalizations l10n) => switch (step) {
    SyncStep.connecting => l10n.syncStepConnecting,
    SyncStep.settingTime => l10n.syncStepSettingTime,
    SyncStep.readingBattery => l10n.syncStepReadingBattery,
    SyncStep.pulling => _pulling(l10n),
    SyncStep.saving => l10n.syncStepSaving,
    SyncStep.disconnecting => l10n.syncStepDisconnecting,
  };

  String _pulling(AppLocalizations l10n) => switch (kind) {
    null => l10n.syncStepPulling,
    RecordKind.activity => l10n.syncStepPullingActivity,
    RecordKind.heartRate => l10n.syncStepPullingHeartRate,
    RecordKind.spo2 => l10n.syncStepPullingSpo2,
    RecordKind.stress => l10n.syncStepPullingStress,
    RecordKind.hrv => l10n.syncStepPullingHrv,
    RecordKind.sleep => l10n.syncStepPullingSleep,
  };

  double get fraction {
    final position = switch (step) {
      SyncStep.connecting ||
      SyncStep.settingTime ||
      SyncStep.readingBattery => step.index,
      SyncStep.pulling => _pullSteps + (kind?.index ?? 0),
      SyncStep.saving ||
      SyncStep.disconnecting => step.index - 1 + RecordKind.values.length,
    };
    return (position + 1) / _positions;
  }
}

extension SyncErrorLabels on SyncError {
  String title(AppLocalizations l10n) => switch (this) {
    CapabilitiesFailed() => l10n.syncPartialTitle,
    NoPairedRing() ||
    AnotherSyncRunning() ||
    SyncAborted() => l10n.syncFailedTitle,
  };

  String message(AppLocalizations l10n) => switch (this) {
    NoPairedRing() => l10n.syncErrorNoRing,
    AnotherSyncRunning() => l10n.syncErrorBusy,
    SyncAborted(:final step) => _aborted(l10n, step),
    CapabilitiesFailed(:final capabilities) => l10n.syncErrorPartial(
      [for (final c in capabilities) c.label(l10n)].join(', '),
    ),
  };

  bool get partial => this is CapabilitiesFailed;

  static String _aborted(AppLocalizations l10n, SyncStep step) =>
      switch (step) {
        SyncStep.connecting => l10n.syncErrorConnecting,
        SyncStep.settingTime => l10n.syncErrorSettingTime,
        SyncStep.saving => l10n.syncErrorSaving,
        SyncStep.readingBattery ||
        SyncStep.pulling ||
        SyncStep.disconnecting => l10n.syncErrorStopped,
      };
}

extension RingCapabilityLabels on RingCapability {
  String label(AppLocalizations l10n) => switch (this) {
    RingCapability.battery => l10n.capabilityBattery,
    RingCapability.activity => l10n.capabilityActivity,
    RingCapability.heartRateLog => l10n.capabilityHeartRate,
    RingCapability.spo2 => l10n.capabilitySpo2,
    RingCapability.stress => l10n.capabilityStress,
    RingCapability.hrv => l10n.capabilityHrv,
    RingCapability.sleep => l10n.capabilitySleep,
    RingCapability.liveHeartRate => l10n.capabilityLiveHeartRate,
    RingCapability.liveSpo2 => l10n.capabilityLiveSpo2,
    RingCapability.heartRateInterval => l10n.capabilityHeartRateInterval,
    RingCapability.autoMonitors => l10n.capabilityAutoMonitors,
    RingCapability.findDevice => l10n.capabilityFindDevice,
  };
}
