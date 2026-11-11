import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';

final class FakeWidgetGateway implements WidgetGateway {
  new({this.pinSupported = true, this.pinFails = false});

  final bool pinSupported;
  final bool pinFails;
  final Map<String, List<Map<String, Object?>>> published = {};
  final List<HomeWidgetKind> pinned = [];

  List<Map<String, Object?>> get snapshots =>
      published[WidgetKeys.snapshot] ?? const [];

  List<Map<String, Object?>> get appearances =>
      published[WidgetKeys.appearance] ?? const [];

  @override
  Future<void> publish(String key, String json) async {
    final decoded = jsonDecode(json) as Map<String, Object?>;
    published.putIfAbsent(key, () => []).add(decoded);
  }

  @override
  Future<bool> canPin() async => pinSupported;

  @override
  Future<void> pin(HomeWidgetKind kind) async {
    if (pinFails) throw PlatformException(code: 'pin_failed');
    pinned.add(kind);
  }
}

final class MutableRingStatusReader implements RingStatusReader {
  new(this.value);

  RingStatus value;

  @override
  Future<RingStatus> status() async => value;
}
