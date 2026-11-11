import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/presentation/readiness_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_config_screen.dart';
import 'package:open_ring/features/widgets/presentation/widgets_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';

import '../../helpers/layout_harness.dart';
import '../../helpers/metrics_fakes.dart';
import '../../helpers/protocol_lab_fakes.dart';
import '../../helpers/ring_fakes.dart';
import '../../helpers/widget_fakes.dart';
import '../../helpers/workout_fakes.dart';

const _kotlinLinks =
    'android/app/src/main/kotlin/gbs/openring/app/widget/WidgetParts.kt';

Future<void> pumpApp(WidgetTester tester) => pumpScaled(
  tester,
  const OpenRingApp(),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  size: const Size(360, 2400),
  overrides: [
    ...protocolLabOverrides(),
    ...ringOverrides(),
    ...WorkoutRig().overrides(),
    ringStatusReaderProvider.overrideWithValue(FakeRingStatusReader(freshRing)),
    widgetGatewayProvider.overrideWithValue(FakeWidgetGateway()),
    todayWidgetConfigStoreProvider.overrideWithValue(
      InMemoryTodayWidgetConfigStore(),
    ),
  ],
);

Future<void> openLink(WidgetTester tester, Uri link) async {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', {
      'location': link.toString(),
      'state': null,
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  final screens = <HomeWidgetKind, Type>{
    HomeWidgetKind.readiness: ReadinessScreen,
    HomeWidgetKind.today: TodayScreen,
    HomeWidgetKind.ring: RingScreen,
    HomeWidgetKind.workout: WorkoutPickScreen,
  };

  for (final MapEntry(key: kind, value: screen) in screens.entries) {
    testWidgets('the ${kind.name} widget link opens $screen', (tester) async {
      await pumpApp(tester);
      await openLink(tester, HomeWidgetKind.ring.deepLink);

      await openLink(tester, kind.deepLink);

      expect(find.byType(screen), findsOneWidget);
    });
  }

  testWidgets('the configure link opens the Today widget config', (
    tester,
  ) async {
    await pumpApp(tester);

    await openLink(tester, todayWidgetConfigLink);

    expect(find.byType(TodayWidgetConfigScreen), findsOneWidget);
  });

  testWidgets('Settings leads to the widgets and the Today widget config', (
    tester,
  ) async {
    await pumpApp(tester);
    await openLink(tester, Uri.parse('openring://widget/ring/settings'));

    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.widgetsKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(SettingsScreen.widgetsKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.widgetsKey));
    await tester.pumpAndSettle();
    expect(find.byType(WidgetsScreen), findsOneWidget);

    await tester.ensureVisible(find.byKey(WidgetsScreen.configureKey));
    await tester.tap(find.byKey(WidgetsScreen.configureKey));
    await tester.pumpAndSettle();
    expect(find.byType(TodayWidgetConfigScreen), findsOneWidget);
    expect(
      find.byKey(TodayWidgetConfigScreen.metricKey(WidgetMetric.sleep)),
      findsOneWidget,
    );
  });

  test('the Kotlin widgets open the same links the router serves', () {
    final kotlin = File(_kotlinLinks).readAsStringSync();

    for (final link in [
      for (final kind in HomeWidgetKind.values) kind.deepLink,
      todayWidgetConfigLink,
    ]) {
      expect(kotlin, contains('"$link"'), reason: '$link');
    }
  });
}
