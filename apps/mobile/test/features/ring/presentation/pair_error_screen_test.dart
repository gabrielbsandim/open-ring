import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/features/ring/presentation/pair_error_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';

import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/protocol_lab_fakes.dart';
import '../../../helpers/ring_fakes.dart';

Future<FakeAppPermissions> _pump(
  WidgetTester tester,
  PairFailure failure, {
  FakeAppPermissions? permissions,
  FakeRingScanner? scanner,
}) async {
  final fake = permissions ?? FakeAppPermissions();
  await pumpOnboardingApp(
    tester,
    at: PairFlow.ring.errorPath(failure.name),
    store: InMemoryOnboardingStore(completed: true),
    overrides: [
      ...protocolLabOverrides(scanner: scanner),
      ...ringOverrides(),
      ...onboardingOverrides(permissions: fake),
    ],
  );
  return fake;
}

void main() {
  test('an unknown reason reads as not found', () {
    expect(PairErrorScreen.parse('bluetoothOff'), PairFailure.bluetoothOff);
    expect(PairErrorScreen.parse('nonsense'), PairFailure.notFound);
    expect(PairErrorScreen.parse(null), PairFailure.notFound);
  });

  testWidgets('not found lists four causes and the model note', (tester) async {
    await _pump(tester, PairFailure.notFound);

    expect(find.text('Ring not found'), findsOneWidget);
    expect(find.text('Charge the ring'), findsOneWidget);
    expect(find.text('Unpair it in QRing and on the phone'), findsOneWidget);
    expect(find.byKey(PairErrorKeys.openSettings), findsNothing);
    expect(find.textContaining('only tested on the COLMI R09'), findsNothing);

    await tapAndSettle(tester, find.byKey(PairErrorKeys.modelToggle));

    expect(find.textContaining('only tested on the COLMI R09'), findsOneWidget);
  });

  testWidgets('a denied permission points to the settings', (tester) async {
    final permissions = await _pump(tester, PairFailure.permissionDenied);

    expect(find.text('Bluetooth access is off'), findsOneWidget);
    expect(find.byKey(PairErrorKeys.modelToggle), findsNothing);

    await tapAndSettle(tester, find.byKey(PairErrorKeys.openSettings));

    expect(permissions.settingsOpened, 1);
  });

  testWidgets('Bluetooth off explains how to turn it on', (tester) async {
    await _pump(tester, PairFailure.bluetoothOff);

    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(find.byKey(PairErrorKeys.retry), findsOneWidget);
    expect(find.byKey(PairErrorKeys.openSettings), findsNothing);
  });

  testWidgets('try again returns to the pairing and searches', (tester) async {
    final scanner = FakeRingScanner(found: const [colmiRing]);
    await _pump(tester, PairFailure.bluetoothOff, scanner: scanner);

    await tapAndSettle(tester, find.byKey(PairErrorKeys.retry));

    expect(find.byType(PairErrorScreen), findsNothing);
    expect(find.byType(PairScreen), findsOneWidget);
    expect(scanner.starts, 1);
    expect(find.byKey(PairKeys.device(colmiRing.id)), findsOneWidget);
  });
}
