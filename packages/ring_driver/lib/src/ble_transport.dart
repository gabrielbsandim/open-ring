import 'package:meta/meta.dart';

@immutable
final class GattCharacteristic {
  const new({required this.service, required this.characteristic});

  final String service;
  final String characteristic;

  @override
  bool operator ==(Object other) =>
      other is GattCharacteristic &&
      other.service.toLowerCase() == service.toLowerCase() &&
      other.characteristic.toLowerCase() == characteristic.toLowerCase();

  @override
  int get hashCode =>
      Object.hash(service.toLowerCase(), characteristic.toLowerCase());
}

enum TransportState { disconnected, connecting, connected }

final class BleTransportException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'BleTransportException: $message';
}

abstract interface class BleTransport {
  Stream<TransportState> get state;

  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> write(GattCharacteristic target, List<int> bytes);
  Stream<List<int>> notifications(GattCharacteristic source);
}
