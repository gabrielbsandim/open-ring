import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/app/theme/theme_mode_controller.dart';
import 'package:open_ring/app/theme/theme_mode_store.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/domain/onboarding_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import 'ble_fakes.dart';
import 'in_memory_theme_mode_store.dart';
import 'onboarding_fakes.dart';
import 'ring_fakes.dart';

const phoneSize = Size(360, 640);
const layoutScales = [1.0, 1.3, 2.0];
const List<Brightness> layoutBrightnesses = Brightness.values;
const layoutLocales = [Locale('en'), Locale('de')];

class LayoutCase {
  const new({
    required this.scale,
    required this.brightness,
    required this.locale,
  });

  final double scale;
  final Brightness brightness;
  final Locale locale;

  TextScaler get textScaler => TextScaler.linear(scale);

  @override
  String toString() => '${scale}x ${brightness.name} $locale';
}

Iterable<LayoutCase> layoutMatrix() sync* {
  for (final scale in layoutScales) {
    for (final brightness in layoutBrightnesses) {
      for (final locale in layoutLocales) {
        yield LayoutCase(scale: scale, brightness: brightness, locale: locale);
      }
    }
  }
}

Widget screenHost(Widget screen) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  localeListResolutionCallback: AppLocales.resolve,
  supportedLocales: AppLocales.supported,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: screen,
);

Future<void> pumpScaled(
  WidgetTester tester,
  Widget widget, {
  required TextScaler textScaler,
  required Brightness brightness,
  required Locale locale,
  ThemeModeStore? themeModeStore,
  OnboardingStore? onboardingStore,
  List<Override>? overrides,
  Size size = phoneSize,
}) async {
  tester.view
    ..devicePixelRatio = 3
    ..physicalSize = size * 3;
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  final data = MediaQueryData.fromView(tester.view)
      .copyWith(textScaler: textScaler, platformBrightness: brightness);
  await expectNoLayoutOverflow(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeModeStoreProvider.overrideWithValue(
            themeModeStore ?? InMemoryThemeModeStore(),
          ),
          onboardingStoreProvider.overrideWithValue(
            onboardingStore ?? InMemoryOnboardingStore(completed: true),
          ),
          ...overrides ?? [...bleOverrides(), ...ringOverrides()],
        ],
        child: MediaQuery(data: data, child: widget),
      ),
    );
    await tester.pumpAndSettle();
  });
}

Future<void> expectNoLayoutOverflow(Future<void> Function() body) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed')) {
      overflows.add(message);
      return;
    }
    previous?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  expect(overflows, isEmpty, reason: 'layout overflowed');
}
