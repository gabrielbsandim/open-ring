import 'dart:async';

import 'package:meta/meta.dart';
import 'package:ring_driver/src/ble_transport.dart';

@immutable
final class GattPacket {
  new(this.characteristic, List<int> bytes) : bytes = List.unmodifiable(bytes);

  final GattCharacteristic characteristic;
  final List<int> bytes;

  @override
  bool operator ==(Object other) {
    if (other is! GattPacket || other.characteristic != characteristic) {
      return false;
    }
    if (other.bytes.length != bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(characteristic, Object.hashAll(bytes));
}

typedef FakeResponder = Iterable<GattPacket> Function(GattPacket write);

final class FakeBleTransport implements BleTransport {
  new({this.responder, this.unreachable = false});

  final FakeResponder? responder;
  final bool unreachable;

  final _state = StreamController<TransportState>.broadcast();
  final _notifications = StreamController<GattPacket>.broadcast();
  final _writes = <GattPacket>[];

  TransportState _current = TransportState.disconnected;
  String? _deviceId;

  TransportState get current => _current;
  String? get deviceId => _deviceId;
  List<GattPacket> get writes => List.unmodifiable(_writes);

  @override
  Stream<TransportState> get state => _state.stream;

  @override
  Future<void> connect(String deviceId) async {
    _set(TransportState.connecting);
    if (unreachable) {
      _set(TransportState.disconnected);
      throw BleTransportException('$deviceId is unreachable');
    }
    _deviceId = deviceId;
    _set(TransportState.connected);
  }

  @override
  Future<void> disconnect() async {
    _deviceId = null;
    _set(TransportState.disconnected);
  }

  @override
  Future<void> write(GattCharacteristic target, List<int> bytes) async {
    if (_current != TransportState.connected) {
      throw const BleTransportException('write while not connected');
    }
    final packet = GattPacket(target, bytes);
    _writes.add(packet);
    (responder?.call(packet) ?? const <GattPacket>[]).forEach(emit);
  }

  @override
  Stream<List<int>> notifications(GattCharacteristic source) => _notifications
      .stream
      .where((packet) => packet.characteristic == source)
      .map((packet) => packet.bytes);

  void emit(GattPacket packet) => _notifications.add(packet);

  Future<void> close() async {
    await _state.close();
    await _notifications.close();
  }

  void _set(TransportState next) {
    _current = next;
    _state.add(next);
  }
}
