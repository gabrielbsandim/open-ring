import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/features/ring/application/ring_link_providers.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/ring_scanner.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';

class FakeRingScanner implements RingScanner {
  new({this.found = const [], this.failure});

  final List<DiscoveredDevice> found;
  final BleTransportException? failure;

  final _results = StreamController<List<DiscoveredDevice>>.broadcast();
  final _scanning = StreamController<bool>.broadcast();

  int starts = 0;
  int stops = 0;

  @override
  Stream<List<DiscoveredDevice>> get results => _results.stream;

  @override
  Stream<bool> get isScanning => _scanning.stream;

  @override
  Future<void> start(Duration timeout) async {
    starts++;
    final error = failure;
    if (error != null) throw error;
    _scanning.add(true);
    _results.add(found);
  }

  @override
  Future<void> stop() async {
    stops++;
    _scanning.add(false);
  }
}

List<Override> bleOverrides({BleTransport? transport, RingScanner? scanner}) =>
    [
      bleTransportProvider.overrideWithValue(transport ?? FakeBleTransport()),
      ringScannerProvider.overrideWithValue(scanner ?? FakeRingScanner()),
    ];
