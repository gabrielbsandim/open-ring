import 'package:meta/meta.dart';

@immutable
final class RingStatus {
  const new({
    required this.paired,
    this.name,
    this.model,
    this.firmware,
    this.lastSyncAt,
    this.batteryPercent,
    this.batteryCharging,
    this.batteryAt,
  });

  static const unpaired = RingStatus(paired: false);

  final bool paired;
  final String? name;
  final String? model;
  final String? firmware;
  final DateTime? lastSyncAt;
  final int? batteryPercent;
  final bool? batteryCharging;
  final DateTime? batteryAt;
}

abstract interface class RingStatusReader {
  Future<RingStatus> status();
}

final class EmptyRingStatusReader implements RingStatusReader {
  const new();

  @override
  Future<RingStatus> status() async => RingStatus.unpaired;
}
