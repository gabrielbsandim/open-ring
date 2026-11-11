import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';

typedef WidgetAppearance = ({
  ThemeMode appTheme,
  TodayWidgetConfig today,
  UnitSystem units,
});

Map<String, Object?> appearanceJson(WidgetAppearance appearance) => {
  'appTheme': appearance.appTheme.name,
  'todayTheme': appearance.today.theme.name,
  'todayMetrics': appearance.today.toJson()['metrics'],
  'units': appearance.units.name,
};

final class WidgetPublisher {
  new(this._gateway);

  final WidgetGateway _gateway;
  final Map<String, String> _published = {};

  Future<void> snapshot(WidgetSnapshot snapshot) =>
      _publish(WidgetKeys.snapshot, snapshot.toJson());

  Future<void> appearance(WidgetAppearance appearance) =>
      _publish(WidgetKeys.appearance, appearanceJson(appearance));

  Future<void> _publish(String key, Map<String, Object?> json) async {
    final encoded = jsonEncode(json);
    if (_published[key] == encoded) return;
    _published[key] = encoded;
    await _gateway.publish(key, encoded);
  }
}
