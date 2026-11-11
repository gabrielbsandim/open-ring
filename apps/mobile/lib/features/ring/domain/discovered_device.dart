import 'package:meta/meta.dart';
import 'package:ring_protocol/ring_protocol.dart';

@immutable
final class DiscoveredDevice {
  const new({
    required this.id,
    required this.name,
    required this.rssi,
    this.serviceUuids = const [],
  });

  static final _colmiName = RegExp(r'^R0\d|colmi', caseSensitive: false);
  static final _colmiRing = RegExp(
    r'^(?:colmi[ _-]?)?(r0\d|r10)(?![0-9])',
    caseSensitive: false,
  );
  static final _colmiRingName = RegExp(
    r'^colmi[ _-]?ring\b',
    caseSensitive: false,
  );

  final String id;
  final String name;
  final int rssi;
  final List<String> serviceUuids;

  String? get colmiModel =>
      _colmiRing.firstMatch(name.trim())?.group(1)?.toUpperCase();

  bool get isColmiRing =>
      colmiModel != null ||
      _colmiRingName.hasMatch(name.trim()) ||
      _hasV1Service;

  bool get _hasV1Service =>
      serviceUuids.any((uuid) => uuid.toLowerCase() == ColmiGatt.v1Service);

  // The scanner reports rings the OS already holds, which do not advertise,
  // with an RSSI of 0.
  bool get heldBySystem => rssi == 0;

  bool get looksLikeColmi => _colmiName.hasMatch(name) || _hasV1Service;

  static List<DiscoveredDevice> rank(Iterable<DiscoveredDevice> devices) =>
      devices.toList()..sort(_compare);

  static int _compare(DiscoveredDevice a, DiscoveredDevice b) {
    if (a.looksLikeColmi == b.looksLikeColmi) return b.rssi.compareTo(a.rssi);
    if (a.looksLikeColmi) return -1;
    return 1;
  }
}
