import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/onboarding/presentation/health_permission_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/fake_health_writer.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

Future<FakeHealthWriter> _pump(
  WidgetTester tester, {
  bool grant = true,
  Set<HealthRecordKind>? denied,
}) async {
  final writer = FakeHealthWriter()..grantOnRequest = grant;
  writer.denied.addAll(denied ?? writableHealthKinds);
  await pumpOnboardingApp(
    tester,
    at: AppPaths.onboardingHealth,
    overrides: [
      ...bleOverrides(),
      ...ringOverrides(),
      ...onboardingOverrides(healthWriter: writer),
    ],
  );
  return writer;
}

void main() {
  testWidgets('lists what is written before asking', (tester) async {
    final writer = await _pump(tester);

    expect(find.text('Connect to Health Connect'), findsOneWidget);
    expect(find.text('Sleep with stages'), findsOneWidget);
    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(writer.requests, isEmpty);
  });

  testWidgets('access granted before the step opens shows it connected', (
    tester,
  ) async {
    final writer = await _pump(tester, denied: const {});

    expect(find.byKey(HealthPermissionKeys.connected), findsOneWidget);
    expect(find.byKey(HealthPermissionKeys.connect), findsNothing);
    expect(find.byKey(HealthPermissionKeys.continueAction), findsOneWidget);
    expect(writer.requests, isEmpty);
  });

  testWidgets('one kind still denied keeps the connect button', (tester) async {
    await _pump(tester, denied: const {HealthRecordKind.sleep});

    expect(find.byKey(HealthPermissionKeys.connect), findsOneWidget);
    expect(find.byKey(HealthPermissionKeys.connected), findsNothing);
  });

  testWidgets('connecting asks the platform and confirms the access', (
    tester,
  ) async {
    final writer = await _pump(tester);

    await tapAndSettle(tester, find.byKey(HealthPermissionKeys.connect));

    expect(writer.requests, hasLength(1));
    expect(find.byKey(HealthPermissionKeys.connected), findsOneWidget);
    expect(find.byKey(HealthPermissionKeys.notNow), findsNothing);

    await tapAndSettle(tester, find.byKey(HealthPermissionKeys.continueAction));

    expect(find.byType(PairScreen), findsOneWidget);
  });

  testWidgets('a declined access says the data stays on the phone', (
    tester,
  ) async {
    final writer = await _pump(tester, grant: false);

    await tapAndSettle(tester, find.byKey(HealthPermissionKeys.connect));

    expect(writer.requests, hasLength(1));
    expect(find.byKey(HealthPermissionKeys.declined), findsOneWidget);
    expect(find.byKey(HealthPermissionKeys.continueAction), findsOneWidget);
  });

  testWidgets('not now skips without asking', (tester) async {
    final writer = await _pump(tester);

    await tapAndSettle(tester, find.byKey(HealthPermissionKeys.notNow));

    expect(writer.requests, isEmpty);
    expect(find.byType(PairScreen), findsOneWidget);
    expect(find.text('Step 4 of 4'), findsOneWidget);
  });
}
