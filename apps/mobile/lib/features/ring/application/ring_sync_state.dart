import 'package:meta/meta.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:ring_driver/ring_driver.dart';

enum SyncStep {
  connecting,
  settingTime,
  readingBattery,
  pulling,
  saving,
  disconnecting,
}

@immutable
final class SyncProgress {
  const new(this.step, {this.kind});

  final SyncStep step;
  final RecordKind? kind;

  @override
  bool operator ==(Object other) =>
      other is SyncProgress && other.step == step && other.kind == kind;

  @override
  int get hashCode => Object.hash(step, kind);

  @override
  String toString() => 'SyncProgress($step, $kind)';
}

@immutable
sealed class SyncError {
  const new();
}

final class NoPairedRing extends SyncError {
  const new();
}

final class AnotherSyncRunning extends SyncError {
  const new();
}

final class SyncAborted extends SyncError {
  const new(this.step, this.message);

  final SyncStep step;
  final String message;
}

final class CapabilitiesFailed extends SyncError {
  new(Iterable<RingCapability> capabilities)
    : capabilities = Set.unmodifiable(capabilities);

  final Set<RingCapability> capabilities;
}

@immutable
final class RingSyncState {
  const new({
    this.progress,
    this.lastSuccessAt,
    this.lastError,
    this.lastWritten = const {},
    this.batteryPercent,
  });

  final SyncProgress? progress;
  final DateTime? lastSuccessAt;
  final SyncError? lastError;
  final Map<RecordKind, int> lastWritten;
  final int? batteryPercent;

  bool get syncing => progress != null;

  RingSyncState at(SyncProgress progress) => RingSyncState(
    progress: progress,
    lastSuccessAt: lastSuccessAt,
    lastError: lastError,
    lastWritten: lastWritten,
    batteryPercent: batteryPercent,
  );

  RingSyncState withBattery(int percent) => RingSyncState(
    progress: progress,
    lastSuccessAt: lastSuccessAt,
    lastError: lastError,
    lastWritten: lastWritten,
    batteryPercent: percent,
  );

  RingSyncState succeeded(
    DateTime at, {
    SyncError? partial,
    Map<RecordKind, int> written = const {},
  }) => RingSyncState(
    lastSuccessAt: at,
    lastError: partial,
    lastWritten: Map.unmodifiable(written),
    batteryPercent: batteryPercent,
  );

  RingSyncState failed(SyncError error) => RingSyncState(
    lastSuccessAt: lastSuccessAt,
    lastError: error,
    lastWritten: lastWritten,
    batteryPercent: batteryPercent,
  );

  RingSyncState withLastSuccess(DateTime? at) => RingSyncState(
    progress: progress,
    lastSuccessAt: at,
    lastError: lastError,
    lastWritten: lastWritten,
    batteryPercent: batteryPercent,
  );

  RingSyncState idle() => RingSyncState(
    lastSuccessAt: lastSuccessAt,
    lastError: lastError,
    lastWritten: lastWritten,
    batteryPercent: batteryPercent,
  );

  RingSyncState afterBackgroundSync(DateTime? at) {
    final last = lastSuccessAt;
    final advanced = at != null && (last == null || at.isAfter(last));
    final stale = advanced || lastError is AnotherSyncRunning;
    return RingSyncState(
      progress: progress,
      lastSuccessAt: advanced ? at : last,
      lastError: stale ? null : lastError,
      lastWritten: lastWritten,
      batteryPercent: batteryPercent,
    );
  }
}
