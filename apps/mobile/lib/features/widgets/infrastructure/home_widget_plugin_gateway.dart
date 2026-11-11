import 'dart:io';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';

const iosAppGroupId = 'group.gbs.openring.app';

abstract base class HomeWidgetPluginGateway implements WidgetGateway {
  const new();

  static WidgetGateway forPlatform() {
    if (Platform.isAndroid) return const AndroidHomeWidgetGateway();
    if (Platform.isIOS) return const IosHomeWidgetGateway();
    return const UnsupportedWidgetGateway();
  }

  Future<void> refresh(HomeWidgetKind kind);

  // A widget that is not on any home screen, or an iOS build without the
  // WidgetKit extension, must never fail the sync that publishes.
  @override
  Future<void> publish(String key, String json) async {
    try {
      await HomeWidget.saveWidgetData<String>(key, json);
      for (final kind in HomeWidgetKind.values) {
        await refresh(kind);
      }
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}

final class AndroidHomeWidgetGateway extends HomeWidgetPluginGateway {
  const new();

  @override
  Future<void> refresh(HomeWidgetKind kind) =>
      HomeWidget.updateWidget(qualifiedAndroidName: kind.androidName);

  @override
  Future<bool> canPin() async {
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> pin(HomeWidgetKind kind) =>
      HomeWidget.requestPinWidget(qualifiedAndroidName: kind.androidName);
}

final class IosHomeWidgetGateway extends HomeWidgetPluginGateway {
  const new();

  @override
  Future<void> publish(String key, String json) async {
    try {
      await HomeWidget.setAppGroupId(iosAppGroupId);
    } on PlatformException {
      return;
    }
    await super.publish(key, json);
  }

  @override
  Future<void> refresh(HomeWidgetKind kind) =>
      HomeWidget.updateWidget(iOSName: kind.iosName);

  @override
  Future<bool> canPin() async => false;

  @override
  Future<void> pin(HomeWidgetKind kind) async {}
}
