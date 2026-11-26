import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../support/what_if_fixtures.dart';
import 'trajectory_screen_fixtures.dart';

Future<void> _pump(
  WidgetTester tester,
  TrajectoryView view, {
  double scale = 1,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  Size size = const Size(360, 4000),
}) => pumpScaled(
  tester,
  screenHost(const TrajectoryScreen()),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: locale,
  size: size,
  overrides: whatIfOverrides(view: view),
);

void main() {
  group('TR10b acceptance 4: the link shows on Ready, Guard and Building', () {
    final shown = <String, TrajectoryView>{
      'ready': readyView(),
      'guard': guardView,
      'building': const TrajectoryBuilding(null),
    };
    for (final MapEntry(:key, :value) in shown.entries) {
      testWidgets('$key shows the what if link', (tester) async {
        await _pump(tester, value);

        expect(find.byKey(TrajectoryKeys.whatIfLink), findsOneWidget);
      });
    }
  });

  group('TR10b acceptance 3: no link when refused, off or failed', () {
    final hidden = <String, TrajectoryView>{
      'underage': const TrajectoryRefused(TrajectoryRefusal.underage),
      'pregnancy': const TrajectoryRefused(TrajectoryRefusal.pregnancy),
      'no height': const TrajectoryRefused(TrajectoryRefusal.noHeight),
      'off': const TrajectoryOff(),
      'error': const TrajectoryError('boom'),
    };
    for (final MapEntry(:key, :value) in hidden.entries) {
      testWidgets('$key shows no what if link', (tester) async {
        await _pump(tester, value);

        expect(find.byKey(TrajectoryKeys.whatIfLink), findsNothing);
      });
    }
  });

  group('TR10b acceptance 9: the link does not overflow', () {
    for (final layout in layoutMatrix()) {
      testWidgets('ready at $layout', (tester) async {
        await _pump(
          tester,
          readyView(),
          scale: layout.scale,
          brightness: layout.brightness,
          locale: layout.locale,
          size: phoneSize,
        );
        await expectNoLayoutOverflow(() async {
          await tester.scrollUntilVisible(
            find.byKey(TrajectoryKeys.whatIfLink),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        });

        expect(find.byKey(TrajectoryKeys.whatIfLink), findsOneWidget);
      });
    }
  });
}
