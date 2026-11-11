import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/onboarding/presentation/first_sync_screen.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/presentation/pair_error_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';
import 'package:ring_driver/testing.dart';

import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/protocol_lab_fakes.dart';
import '../../../helpers/ring_fakes.dart';

final class _Rig {
  new({
    List<DiscoveredDevice> found = const [colmiRing, bondedRing, otherBand],
    bool unreachable = false,
  }) : scanner = FakeRingScanner(found: found),
       transport = FakeBleTransport(unreachable: unreachable);

  final FakeRingScanner scanner;
  final FakeBleTransport transport;
  final permissions = FakeAppPermissions();
  final radio = FakeBluetoothRadio();
  final pairedStore = RecordingPairedRingStore();
  final onboarding = InMemoryOnboardingStore();

  Future<void> pump(WidgetTester tester, {PairFlow flow = PairFlow.ring}) =>
      pumpOnboardingApp(
        tester,
        at: flow.path,
        store: onboarding..completed = flow == PairFlow.ring,
        overrides: [
          ...protocolLabOverrides(scanner: scanner, transport: transport),
          ...ringOverrides(),
          ...onboardingOverrides(
            permissions: permissions,
            radio: radio,
            pairedStore: pairedStore,
          ),
        ],
      );
}

const ringTwo = DiscoveredDevice(
  id: 'AA:BB:CC:00:00:0B',
  name: 'COLMI Ring 2',
  rssi: -58,
);

void main() {
  testWidgets('explains how to wake the ring before searching', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);

    expect(find.text('No ring paired'), findsOneWidget);
    expect(find.byKey(PairKeys.search), findsOneWidget);
    expect(rig.scanner.starts, 0);
    expect(rig.permissions.requests, isEmpty);
  });

  testWidgets('lists only COLMI rings and marks the one the phone holds', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);

    await tapAndSettle(tester, find.byKey(PairKeys.search));

    expect(find.byKey(PairKeys.device(colmiRing.id)), findsOneWidget);
    expect(find.byKey(PairKeys.device(bondedRing.id)), findsOneWidget);
    expect(find.byKey(PairKeys.device(otherBand.id)), findsNothing);
    expect(find.text('COLMI R09'), findsOneWidget);
    expect(find.text('R09_F800 · compatible'), findsOneWidget);
    expect(find.text('R02_1A2B · may work, untested'), findsOneWidget);
    expect(find.text('Strong signal'), findsOneWidget);
    expect(find.text('Already paired to this phone'), findsOneWidget);
  });

  testWidgets(
    'a ring without a model in its name shows that name and no claim',
    (tester) async {
      final rig = _Rig(found: const [ringTwo]);
      await rig.pump(tester);
      await tapAndSettle(tester, find.byKey(PairKeys.search));

      expect(find.text('COLMI Ring 2'), findsOneWidget);
      expect(find.text('model shown after pairing'), findsOneWidget);
      expect(find.textContaining('untested'), findsNothing);
      expect(find.text('COLMI'), findsNothing);

      await tapAndSettle(tester, find.byKey(PairKeys.device(ringTwo.id)));

      expect(find.text('COLMI Ring 2 paired'), findsOneWidget);
      expect(rig.pairedStore.saved.single.name, 'COLMI Ring 2');
      expect(rig.pairedStore.saved.single.model, isNull);
    },
  );

  testWidgets('pairing saves the ring and moves on to the first sync', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await tapAndSettle(tester, find.byKey(PairKeys.search));

    await tapAndSettle(tester, find.byKey(PairKeys.device(bondedRing.id)));

    expect(find.byKey(PairKeys.paired), findsOneWidget);
    expect(find.text('COLMI R02 paired'), findsOneWidget);
    expect(rig.pairedStore.saved.single.deviceId, bondedRing.id);

    await tapAndSettle(tester, find.byKey(PairKeys.continueAction));

    expect(find.byType(FirstSyncScreen), findsOneWidget);
  });

  testWidgets('pairing during onboarding finishes the onboarding', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester, flow: PairFlow.onboarding);
    expect(find.text('Step 4 of 4'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(PairKeys.search));

    await tapAndSettle(tester, find.byKey(PairKeys.device(colmiRing.id)));

    expect(rig.onboarding.completed, isTrue);
    expect(rig.onboarding.writes, 1);
  });

  testWidgets('a ring that does not answer can be tapped again', (
    tester,
  ) async {
    final rig = _Rig(unreachable: true);
    await rig.pump(tester);
    await tapAndSettle(tester, find.byKey(PairKeys.search));

    await tapAndSettle(tester, find.byKey(PairKeys.device(colmiRing.id)));

    expect(find.byKey(PairKeys.connectFailed), findsOneWidget);
    expect(find.byKey(PairKeys.device(colmiRing.id)), findsOneWidget);
    expect(find.byKey(PairKeys.searchAgain), findsOneWidget);
    expect(rig.pairedStore.saved, isEmpty);
  });

  testWidgets('a scan that ends empty opens the not found help', (
    tester,
  ) async {
    final rig = _Rig(found: const [otherBand]);
    await rig.pump(tester);
    await tapAndSettle(tester, find.byKey(PairKeys.search));

    await rig.scanner.stop();
    await tester.pumpAndSettle();

    expect(find.byType(PairErrorScreen), findsOneWidget);
    expect(find.text('Ring not found'), findsOneWidget);
  });

  testWidgets('a denied permission opens its help', (tester) async {
    final rig = _Rig();
    rig.permissions.grantOnRequest = false;
    await rig.pump(tester);

    await tapAndSettle(tester, find.byKey(PairKeys.search));

    expect(find.text('Bluetooth access is off'), findsOneWidget);
    expect(rig.scanner.starts, 0);
  });

  testWidgets('a radio that stays off opens its help', (tester) async {
    final rig = _Rig();
    rig.radio.on = false;
    await rig.pump(tester);

    await tapAndSettle(tester, find.byKey(PairKeys.search));

    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(rig.scanner.starts, 0);
  });

  testWidgets('the not found link is reachable while scanning', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);
    await tapAndSettle(tester, find.byKey(PairKeys.search));

    await tapAndSettle(tester, find.byKey(PairKeys.notFound));

    expect(
      tester.widget<PairErrorScreen>(find.byType(PairErrorScreen)).failure,
      PairFailure.notFound,
    );
  });
}
