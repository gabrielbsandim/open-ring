import 'package:meta/meta.dart';
import 'package:open_ring/features/ring/domain/checksum_rule.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:open_ring/features/ring/domain/raw_frame.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_protocol/ring_protocol.dart';

@immutable
sealed class LabNotice {
  const new();
}

final class TransportFailure extends LabNotice {
  const new(this.message);

  final String message;
}

final class ExportFailure extends LabNotice {
  const new(this.message);

  final String message;
}

final class RawFrameRejected extends LabNotice {
  const new(this.error, {this.byteCount = 0});

  final RawFrameError error;
  final int byteCount;
}

@immutable
final class StopProbe {
  const new({
    this.type = RealTimeType.heartRate,
    this.stopSent = false,
    this.before = 0,
    this.after = 0,
  });

  final RealTimeType type;
  final bool stopSent;
  final int before;
  final int after;

  StopProbe counted() => StopProbe(
    type: type,
    stopSent: stopSent,
    before: stopSent ? before : before + 1,
    after: stopSent ? after + 1 : after,
  );

  StopProbe stopped() =>
      StopProbe(type: type, stopSent: true, before: before, after: after);

  @override
  bool operator ==(Object other) =>
      other is StopProbe &&
      other.type == type &&
      other.stopSent == stopSent &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(type, stopSent, before, after);
}

@immutable
final class ProtocolLabState {
  const new({
    this.devices = const [],
    this.scanning = false,
    this.link = TransportState.disconnected,
    this.device,
    this.log = const [],
    this.checksum = ChecksumRule.masked,
    this.notice,
    this.stopProbe,
  });

  final List<DiscoveredDevice> devices;
  final bool scanning;
  final TransportState link;
  final DiscoveredDevice? device;
  final List<FrameLogEntry> log;
  final ChecksumRule checksum;
  final LabNotice? notice;
  final StopProbe? stopProbe;

  bool get connected => link == TransportState.connected;

  ProtocolLabState copyWith({
    List<DiscoveredDevice>? devices,
    bool? scanning,
    TransportState? link,
    List<FrameLogEntry>? log,
    ChecksumRule? checksum,
    StopProbe? stopProbe,
  }) => ProtocolLabState(
    devices: devices ?? this.devices,
    scanning: scanning ?? this.scanning,
    link: link ?? this.link,
    device: device,
    log: log ?? this.log,
    checksum: checksum ?? this.checksum,
    notice: notice,
    stopProbe: stopProbe ?? this.stopProbe,
  );

  ProtocolLabState withDevice(DiscoveredDevice? device) => ProtocolLabState(
    devices: devices,
    scanning: scanning,
    link: link,
    device: device,
    log: log,
    checksum: checksum,
    notice: notice,
    stopProbe: stopProbe,
  );

  ProtocolLabState withNotice(LabNotice? notice) => ProtocolLabState(
    devices: devices,
    scanning: scanning,
    link: link,
    device: device,
    log: log,
    checksum: checksum,
    notice: notice,
    stopProbe: stopProbe,
  );
}
