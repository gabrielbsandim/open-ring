import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/settings/application/notification_providers.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/live_workout_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';
import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

const _english = LayoutCase(
  scale: 1,
  brightness: Brightness.dark,
  locale: Locale('en'),
);

FakeAppPermissions _permissions(
  PermissionStatus status, {
  bool grantOnRequest = true,
}) => FakeAppPermissions(
  statuses: {AppPermission.notifications: status},
  grantOnRequest: grantOnRequest,
);

final class _BusyPermissions extends FakeAppPermissions {
  new(this.error)
    : super(statuses: {AppPermission.notifications: PermissionStatus.denied});

  final Exception error;

  @override
  Future<PermissionStatus> request(AppPermission permission) async {
    requests.add(permission);
    throw error;
  }
}

final class _HeldPermissions extends FakeAppPermissions {
  new()
    : super(statuses: {AppPermission.notifications: PermissionStatus.denied});

  final hold = Completer<void>();
  int asked = 0;

  @override
  Future<PermissionStatus> request(AppPermission permission) async {
    asked++;
    await hold.future;
    return await super.request(permission);
  }
}

Future<void> _pump(
  WidgetTester tester,
  FakeAppPermissions permissions, {
  InMemoryNotificationAccess? access,
  LayoutCase c = _english,
  Size size = tallPhone,
}) => pumpWorkout(
  tester,
  const WorkoutPickScreen(),
  WorkoutRig(),
  c: c,
  size: size,
  overrides: [
    appPermissionsProvider.overrideWithValue(permissions),
    notificationAccessProvider.overrideWithValue(
      access ?? InMemoryNotificationAccess(allowed: false),
    ),
  ],
);

Future<void> _tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

FilledButton _allowButton(WidgetTester tester) => tester.widget(
  find.descendant(
    of: find.byKey(WorkoutPickKeys.notificationsAllow),
    matching: find.byType(FilledButton),
  ),
);

final Finder _card = find.byKey(WorkoutPickKeys.notifications);
final Finder _allow = find.byKey(WorkoutPickKeys.notificationsAllow);
final Finder _settings = find.byKey(WorkoutPickKeys.notificationsSettings);

void main() {
  group('1. notifications denied', () {
    testWidgets('shows the title, the body and Allow, not Settings', (
      tester,
    ) async {
      await _pump(tester, _permissions(PermissionStatus.denied));

      expect(_card, findsOneWidget);
      expect(find.text('Notifications off'), findsOneWidget);
      expect(
        find.text(
          'The workout still records, but its time, heart rate and buttons '
          'do not show outside the app or on the lock screen.',
        ),
        findsOneWidget,
      );
      expect(find.text('Allow notifications'), findsOneWidget);
      expect(_allow, findsOneWidget);
      expect(_settings, findsNothing);
    });
  });

  group('2 and 3. Allow notifications', () {
    testWidgets('a grant asks once and the card goes', (tester) async {
      final permissions = _permissions(PermissionStatus.denied);
      await _pump(tester, permissions);

      await _tap(tester, WorkoutPickKeys.notificationsAllow);

      expect(permissions.requests, [AppPermission.notifications]);
      expect(_card, findsNothing);
    });

    testWidgets('a refusal puts Settings in place of Allow', (tester) async {
      final permissions = _permissions(
        PermissionStatus.denied,
        grantOnRequest: false,
      );
      await _pump(tester, permissions);

      await _tap(tester, WorkoutPickKeys.notificationsAllow);

      expect(permissions.requests, [AppPermission.notifications]);
      expect(_card, findsOneWidget);
      expect(_allow, findsNothing);
      expect(_settings, findsOneWidget);
      expect(find.text('Open notification settings'), findsOneWidget);
    });
  });

  testWidgets('4. permanently denied opens the settings and never asks', (
    tester,
  ) async {
    final permissions = _permissions(PermissionStatus.permanentlyDenied);
    final access = InMemoryNotificationAccess(allowed: false);
    await _pump(tester, permissions, access: access);

    expect(_allow, findsNothing);
    await _tap(tester, WorkoutPickKeys.notificationsSettings);

    expect(access.settingsOpened, 1);
    expect(permissions.requests, isEmpty);
    expect(permissions.settingsOpened, 0);
  });

  group('5. nothing to ask', () {
    for (final status in [
      PermissionStatus.granted,
      PermissionStatus.notApplicable,
    ]) {
      testWidgets('${status.name} shows no card', (tester) async {
        await _pump(tester, _permissions(status));

        expect(_card, findsNothing);
        expect(find.text('Notifications off'), findsNothing);
      });
    }
  });

  group('6. a port that fails', () {
    testWidgets('no permissions port shows no card and throws nothing', (
      tester,
    ) async {
      await pumpWorkout(
        tester,
        const WorkoutPickScreen(),
        WorkoutRig(),
        size: tallPhone,
      );

      expect(tester.takeException(), isNull);
      expect(_card, findsNothing);
      expect(find.byKey(WorkoutPickKeys.start), findsOneWidget);
    });

    testWidgets('a request that is not a platform error still frees Allow', (
      tester,
    ) async {
      final permissions = _BusyPermissions(const FormatException('no request'));
      await _pump(tester, permissions);

      await _tap(tester, WorkoutPickKeys.notificationsAllow);

      expect(tester.takeException(), isNull);
      expect(_allowButton(tester).onPressed, isNotNull);
      permissions.statuses[AppPermission.notifications] =
          PermissionStatus.granted;
      await _resume(tester);
      expect(_card, findsNothing);
    });

    testWidgets('a busy request keeps the card as it was', (tester) async {
      final permissions = _BusyPermissions(PlatformException(code: 'busy'));
      await _pump(tester, permissions);

      await _tap(tester, WorkoutPickKeys.notificationsAllow);

      expect(tester.takeException(), isNull);
      expect(permissions.requests, [AppPermission.notifications]);
      expect(_card, findsOneWidget);
      expect(_allow, findsOneWidget);
      expect(_allowButton(tester).onPressed, isNotNull);
    });

    testWidgets('the answer of the request wins over the resume it causes', (
      tester,
    ) async {
      final permissions = _HeldPermissions();
      await _pump(tester, permissions);

      await _tap(tester, WorkoutPickKeys.notificationsAllow);
      expect(_allowButton(tester).onPressed, isNull);
      permissions.statuses[AppPermission.notifications] =
          PermissionStatus.permanentlyDenied;
      await _resume(tester);
      expect(_allow, findsOneWidget);
      expect(_settings, findsNothing);

      permissions.hold.complete();
      await tester.pumpAndSettle();

      expect(permissions.asked, 1);
      expect(_card, findsNothing);
    });

    testWidgets('an answer after the screen closed changes nothing', (
      tester,
    ) async {
      final permissions = _HeldPermissions();
      await _pump(tester, permissions);

      await _tap(tester, WorkoutPickKeys.notificationsAllow);
      await tester.pumpWidget(const SizedBox());
      permissions.hold.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(permissions.requests, [AppPermission.notifications]);
    });
  });

  testWidgets('7. a grant made outside the app hides the card on return', (
    tester,
  ) async {
    final permissions = _permissions(PermissionStatus.denied);
    await _pump(tester, permissions);
    expect(_card, findsOneWidget);

    permissions.statuses[AppPermission.notifications] =
        PermissionStatus.granted;
    await _resume(tester);

    expect(_card, findsNothing);
    expect(permissions.requests, isEmpty);
  });

  testWidgets('8. the card never blocks Start', (tester) async {
    final rig = WorkoutRig();
    await pumpScaled(
      tester,
      const OpenRingApp(),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      size: tallPhone,
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...rig.overrides(),
        ringStatusReaderProvider.overrideWithValue(
          FakeRingStatusReader(pairedRing),
        ),
        appPermissionsProvider.overrideWithValue(
          _permissions(PermissionStatus.denied),
        ),
      ],
    );
    await tester.tap(
      find.byKey(AppNavigationBar.destinationKey(AppTab.activity)),
    );
    await tester.pumpAndSettle();
    await _tap(tester, WorkoutEntryButton.startKey);
    await _tap(tester, WorkoutPickKeys.type(WorkoutType.strength));
    expect(_card, findsOneWidget);

    await _tap(tester, WorkoutPickKeys.start);

    expect(find.byType(LiveWorkoutScreen), findsOneWidget);
    expect(workoutContainer(tester).read(workoutProvider).live, isTrue);
  });

  group('9. the card lays out', () {
    for (final status in [
      PermissionStatus.denied,
      PermissionStatus.permanentlyDenied,
    ]) {
      for (final c in layoutMatrix()) {
        testWidgets('${status.name} at $c', (tester) async {
          await _pump(tester, _permissions(status), c: c, size: phoneSize);

          await scrollThrough(tester);
          expect(
            find.byKey(WorkoutPickKeys.notifications, skipOffstage: false),
            findsOneWidget,
          );
        });
      }
    }
  });

  testWidgets('10. the card reads in Portuguese', (tester) async {
    await _pump(
      tester,
      _permissions(PermissionStatus.denied),
      c: const LayoutCase(
        scale: 1,
        brightness: Brightness.light,
        locale: Locale('pt'),
      ),
    );

    expect(find.text('Notificações desligadas'), findsOneWidget);
    expect(
      find.text(
        'O treino grava normalmente, mas o tempo, a FC e os botões não '
        'aparecem fora do app nem na tela de bloqueio.',
      ),
      findsOneWidget,
    );
    expect(find.text('Permitir notificações'), findsOneWidget);
  });
}
