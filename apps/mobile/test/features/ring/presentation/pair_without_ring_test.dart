import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
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
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/fake_sync_scheduler.dart';
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
  Future<bool> backgroundReadAllowed() => inner.backgroundReadAllowed();

  @override
  Future<bool> requestBackgroundReadAccess() =>
      inner.requestBackgroundReadAccess();

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

// Holds connect open so the connecting phase renders before it fails.
final class _SlowFailingTransport implements BleTransport {
  final release = Completer<void>();

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  Future<void> connect(String deviceId) async {
    await release.future;
    throw const BleTransportException('unreachable');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> write(GattCharacteristic target, List<int> bytes) async {}

  @override
  Stream<List<int>> notifications(GattCharacteristic source) =>
      const Stream.empty();
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
  final scheduler = FakeSyncScheduler();
  late final ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    PairFlow flow = PairFlow.onboarding,
    List<Override>? ble,
  }) async {
    container = await pumpOnboardingApp(
      tester,
      at: flow.path,
      store: onboarding..completed = flow == PairFlow.ring,
      overrides: [
        ...ble ?? bleOverrides(),
        ...ringOverrides(scheduler: scheduler),
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

    testWidgets(
      'criterion 6: continuing asks for background read access once',
      (tester) async {
        final rig = _Rig();
        await rig.pump(tester);

        await tapAndSettle(tester, find.byKey(PairKeys.withoutRing));

        expect(rig.fake.backgroundRequests, 1);
        expect(rig.location, AppTab.today.path);
      },
      variant: _android,
    );

    testWidgets('criterion 6: a granted background read registers the job', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);

      await tapAndSettle(tester, find.byKey(PairKeys.withoutRing));

      expect(rig.scheduler.calls, hasLength(1));
      expect(rig.scheduler.cancels, 0);
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
  testWidgets('a ring tapped mid-run that fails to connect still completes', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final fake = FakeHealthReader();
    final transport = _SlowFailingTransport();
    final rig = _Rig(
      fake: fake,
      reader: _ScriptedReader(fake, (_) => gate.future),
    );
    await rig.pump(
      tester,
      ble: bleOverrides(
        scanner: FakeRingScanner(found: const [colmiRing]),
        transport: transport,
      ),
    );
    final scrollable = find.byType(Scrollable).first;
    final action = find.byKey(PairKeys.withoutRing);
    await tester.scrollUntilVisible(action, 120, scrollable: scrollable);
    await tester.tap(action);
    await tester.pump();

    final search = find.byKey(PairKeys.search);
    await tester.scrollUntilVisible(search, -120, scrollable: scrollable);
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PairKeys.device(colmiRing.id)));
    await tester.pump();
    transport.release.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(PairKeys.connectFailed), findsOneWidget);
    expect(rig.onboarding.writes, 0);

    gate.complete(true);
    await tester.pumpAndSettle();

    expect(rig.onboarding.writes, 1);
    expect(rig.location, AppTab.today.path);
  }, variant: _android);
}
