import 'package:open_ring/app/router/app_routes.dart';

const widgetLinkScheme = 'openring';
const widgetLinkHost = 'widget';

enum HomeWidgetKind {
  readiness('ReadinessWidgetReceiver', AppPaths.readiness),
  today('TodayWidgetReceiver', '/today'),
  ring('RingWidgetReceiver', '/ring'),
  workout('WorkoutWidgetReceiver', AppPaths.workout);

  new(this.receiver, this.path);

  final String receiver;
  final String path;

  String get androidName => 'gbs.openring.app.widget.$receiver';

  String get iosName => 'OpenRing${receiver.replaceAll('Receiver', '')}';

  Uri get deepLink =>
      Uri(scheme: widgetLinkScheme, host: widgetLinkHost, path: path);
}

final Uri todayWidgetConfigLink = Uri(
  scheme: widgetLinkScheme,
  host: widgetLinkHost,
  path: AppPaths.settingsWidgetToday,
);

abstract final class WidgetKeys {
  static const snapshot = 'openring_snapshot';
  static const appearance = 'openring_appearance';
}

abstract interface class WidgetGateway {
  Future<void> publish(String key, String json);

  Future<bool> canPin();

  Future<void> pin(HomeWidgetKind kind);
}

final class UnsupportedWidgetGateway implements WidgetGateway {
  const new();

  @override
  Future<void> publish(String key, String json) async {}

  @override
  Future<bool> canPin() async => false;

  @override
  Future<void> pin(HomeWidgetKind kind) async {}
}
