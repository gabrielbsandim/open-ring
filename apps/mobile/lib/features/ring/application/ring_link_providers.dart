import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/ring/domain/ring_scanner.dart';
import 'package:ring_driver/ring_driver.dart';

final bleTransportProvider = Provider<BleTransport>(
  (ref) => throw UnimplementedError('Override bleTransportProvider.'),
);

final ringScannerProvider = Provider<RingScanner>(
  (ref) => throw UnimplementedError('Override ringScannerProvider.'),
);
