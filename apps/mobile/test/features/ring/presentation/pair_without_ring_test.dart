import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

final class _ScriptedReader implements HealthReader {
  new(this.inner, this.onRequest);

  final FakeHealthReader inner;
  final Future<bool> Function(HealthRecordKind kind) onRequest;

  @override
  Future<HealthAccess> readAccess(HealthRecordKind kind) =>
      inner.readAccess(kind);

  @override
  Future<bool> requestReadAccess(HealthRecordKind kind) {
    inner.requests.add(kind);
    return onRequest(kind);
  }

  @override
  Future<ExternalRead<ExternalSleepNight>> sleepNights({
    required DateTime from,
    required DateTime to,
  }) => inner.sleepNights(from: from, to: to);

  @override
  Future<ExternalRead<ExternalWorkout>> workouts({
    required DateTime from,
    required DateTime to,
  }) => inner.workouts(from: from, to: to);
}

final class _Rig {
  factory({FakeHealthReader? fake, HealthReader? reader}) {
    final shared = fake ?? FakeHealthReader();
    return _Rig._(shared, reader ?? shared);
  }

  new _(this.fake, this.reader);

  final FakeHealthReader fake;
  final HealthReader reader;
  final store = InMemoryHealthReadStore();
  final onboarding = InMemoryOnboardingStore();
  late final ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    PairFlow flow = PairFlow.onboarding,
  }) async {
    container = await pumpOnboardingApp(
      tester,
      at: flow.path,
      store: onboarding..completed = flow == PairFlow.ring,
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...onboardingOverrides(),
        healthReaderProvider.overrideWithValue(reader),
        healthReadStoreProvider.overrideWithValue(store),
      ],
    );
  }

  String get location =>
      container.read(appRouterProvider).routeInformationProvider.value.uri.path;

  Future<bool> enabled(HealthRecordKind kind) async =>
      (await store.settings(kind)).enabled;
}

final _android = TargetPlatformVariant.only(TargetPlatform.android);

ButtonStyleButton _button(WidgetTester tester) {
  final finder = find.byKey(PairKeys.withoutRing);
  final self = tester.widget(finder);
  if (self is ButtonStyleButton) return self;
  return tester.widget<ButtonStyleButton>(
    find.descendant(
      of: finder,
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
}

void main() {
  group('Without a ring visibility', () {
    testWidgets('shows during onboarding on Android', (tester) async {
      await _Rig().pump(tester);

      expect(find.byKey(PairKeys.withoutRing), findsOneWidget);
    }, variant: _android);

    testWidgets('is absent from the ring tab flow on Android', (tester) async {
      await _Rig().pump(tester, flow: PairFlow.ring);

      expect(find.byKey(PairKeys.search), findsOneWidget);
      expect(find.byKey(PairKeys.withoutRing), findsNothing);
    }, variant: _android);

    testWidgets('is absent during onboarding on iOS', (tester) async {
      await _Rig().pump(tester);

      expect(find.byKey(PairKeys.search), findsOneWidget);
      expect(find.byKey(PairKeys.withoutRing), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('Without a ring action', () {
    testWidgets('read access granted enables both reads and lands on today', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);

      await tapAndSettle(tester, find.byKey(PairKeys.withoutRing));

      expect(await rig.enabled(HealthRecordKind.sleep), isTrue);
      expect(await rig.enabled(HealthRecordKind.workout), isTrue);
      // The fake grants every kind at once, so only the first ask is asserted.
      expect(rig.fake.requests.first, HealthRecordKind.sleep);
      expect(rig.onboarding.completed, isTrue);
      expect(rig.container.read(onboardingProvider), isTrue);
      expect(rig.location, AppTab.today.path);
    }, variant: _android);

    testWidgets('read access declined still completes onboarding', (
      tester,
    ) async {
      final rig = _Rig(fake: FakeHealthReader(grantOnRequest: false));
      await rig.pump(tester);

      await tapAndSettle(tester, find.byKey(PairKeys.withoutRing));

      expect(await rig.enabled(HealthRecordKind.sleep), isFalse);
      expect(await rig.enabled(HealthRecordKind.workout), isFalse);
      expect(rig.onboarding.completed, isTrue);
      expect(rig.location, AppTab.today.path);
    }, variant: _android);

    testWidgets('Health Connect not installed still completes onboarding', (
      tester,
    ) async {
      final rig = _Rig(
        fake: FakeHealthReader(
          access: HealthAccess.unavailable,
          grantOnRequest: false,
        ),
      );
      await rig.pump(tester);

      await tapAndSettle(tester, find.byKey(PairKeys.withoutRing));

      expect(await rig.enabled(HealthRecordKind.sleep), isFalse);
      expect(rig.onboarding.completed, isTrue);
      expect(rig.location, AppTab.today.path);
    }, variant: _android);

    testWidgets('a reader that throws still completes onboarding', (
      tester,
    ) async {
      final fake = FakeHealthReader();
      final rig = _Rig(
        fake: fake,
        reader: _ScriptedReader(
          fake,
          (_) async => throw StateError('Health Connect crashed'),
        ),
      );
      await rig.pump(tester);

      await tapAndSettle(tester, find.byKey(PairKeys.withoutRing));

      expect(rig.onboarding.completed, isTrue);
      expect(rig.location, AppTab.today.path);
    }, variant: _android);

    testWidgets('is disabled while it runs and a second tap does nothing', (
      tester,
    ) async {
      final gate = Completer<bool>();
      final fake = FakeHealthReader();
      final rig = _Rig(
        fake: fake,
        reader: _ScriptedReader(fake, (_) => gate.future),
      );
      await rig.pump(tester);
      final action = find.byKey(PairKeys.withoutRing);

      await tester.scrollUntilVisible(
        action,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(action);
      await tester.pump();

      expect(_button(tester).onPressed, isNull);
      await tester.tap(action, warnIfMissed: false);
      await tester.pump();
      expect(fake.requests, [HealthRecordKind.sleep]);
      expect(rig.onboarding.writes, 0);

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(rig.onboarding.writes, 1);
      expect(rig.location, AppTab.today.path);
    }, variant: _android);
  });
  testWidgets('a search started mid-run still completes onboarding', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final fake = FakeHealthReader();
    final rig = _Rig(
      fake: fake,
      reader: _ScriptedReader(fake, (_) => gate.future),
    );
    await rig.pump(tester);
    final action = find.byKey(PairKeys.withoutRing);
    await tester.scrollUntilVisible(
      action,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pump();

    final search = find.byKey(PairKeys.search);
    await tester.scrollUntilVisible(
      search,
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(search);
    await tester.pump();
    expect(find.byKey(PairKeys.search), findsNothing);

    gate.complete(true);
    await tester.pumpAndSettle();

    expect(rig.onboarding.writes, 1);
    expect(rig.location, AppTab.today.path);
  }, variant: _android);
}
