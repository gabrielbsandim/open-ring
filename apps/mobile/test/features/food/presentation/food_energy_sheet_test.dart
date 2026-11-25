import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/domain/food_energy_store.dart';
import 'package:open_ring/features/food/presentation/food_energy_sheet.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';

import '../../../helpers/layout_harness.dart';

const _screenedOn = LocalDate(2026, 11, 20);

final class _SlowStore implements FoodEnergyStore {
  final gate = Completer<void>();
  int writes = 0;

  @override
  Future<FoodEnergyOptIn?> read() async => null;

  @override
  Future<void> write(FoodEnergyOptIn value) async {
    writes++;
    await gate.future;
  }

  @override
  Future<void> clear() async {}
}

final class _Opener extends StatefulWidget {
  const new();

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  bool? result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () async {
            final on = await showFoodEnergyOptInSheet(
              context,
              screenedOn: _screenedOn,
            );
            setState(() => result = on);
          },
          child: const Text('open'),
        ),
        Text('result: $result'),
      ],
    ),
  );
}

Future<_SlowStore> _open(
  WidgetTester tester, {
  FoodEnergyGate gate = const FoodEnergyOffered(_screenedOn),
  double scale = 1,
}) async {
  final store = _SlowStore();
  await pumpScaled(
    tester,
    screenHost(const _Opener()),
    textScaler: TextScaler.linear(scale),
    brightness: Brightness.dark,
    locale: const Locale('en'),
    overrides: [
      clockProvider.overrideWithValue(() => DateTime(2026, 12, 8, 12)),
      foodEnergyGateProvider.overrideWith((ref) async => gate),
      foodEnergyStoreProvider.overrideWithValue(store),
      demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
      goalStoreProvider.overrideWithValue(InMemoryGoalStore()),
    ],
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return store;
}

const _screened =
    'You answered the five Goals questions on Fri, Nov 20, and no answer '
    'asked for soft mode. They count here too.';

const _points =
    'One range a week, on the Week screen. On the photos you analyze, the '
    'model proposes the items in household measures, and you check '
    'them. Soft mode turns this off by itself.';

void main() {
  testWidgets('shows the title, the screening date and the points', (
    tester,
  ) async {
    await _open(tester, scale: 2);

    for (final text in [
      'Turn on Weekly energy?',
      _screened,
      _points,
      'Cancel',
      'Turn on',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('cancel closes with false and writes nothing', (tester) async {
    final store = await _open(tester);

    await tester.tap(find.byKey(FoodEnergySheetKeys.cancel));
    await tester.pumpAndSettle();

    expect(store.writes, 0);
    expect(find.text('result: false'), findsOneWidget);
  });

  testWidgets('a double tap on Turn on writes once', (tester) async {
    final store = await _open(tester);

    await tester.tap(find.byKey(FoodEnergySheetKeys.on));
    await tester.tap(find.byKey(FoodEnergySheetKeys.on), warnIfMissed: false);
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(FoodEnergySheetKeys.on)).onPressed,
      isNull,
    );
    store.gate.complete();
    await tester.pumpAndSettle();

    expect(store.writes, 1);
    expect(find.text('result: true'), findsOneWidget);
  });

  testWidgets('a gate that no longer offers it keeps the sheet open', (
    tester,
  ) async {
    final store = await _open(tester, gate: const FoodEnergyOn(_screenedOn));

    await tester.tap(find.byKey(FoodEnergySheetKeys.on));
    await tester.pumpAndSettle();

    expect(store.writes, 0);
    expect(find.byKey(FoodEnergySheetKeys.sheet), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(FoodEnergySheetKeys.on)).onPressed,
      isNotNull,
    );
  });
}
