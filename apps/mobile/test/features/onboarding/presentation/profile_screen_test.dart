import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/onboarding/presentation/health_permission_screen.dart';
import 'package:open_ring/features/onboarding/presentation/profile_screen.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/protocol_lab_fakes.dart';
import '../../../helpers/ring_fakes.dart';

Future<InMemoryUserProfileStore> _pump(
  WidgetTester tester, [
  UserProfile? saved,
]) async {
  final store = InMemoryUserProfileStore(saved);
  await pumpOnboardingApp(
    tester,
    at: AppPaths.onboardingProfile,
    overrides: [
      ...protocolLabOverrides(),
      ...ringOverrides(),
      ...onboardingOverrides(profileStore: store),
      clockProvider.overrideWithValue(() => DateTime(2026, 11, 10)),
    ],
  );
  return store;
}

Future<void> _type(WidgetTester tester, Key field, String text) async {
  await tester.scrollUntilVisible(
    fieldOf(field),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(fieldOf(field), text);
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, Key field) =>
    tester.widget<TextField>(fieldOf(field)).controller!.text;

FilledButton _continue(WidgetTester tester) => tester.widget(
  find.descendant(
    of: find.byKey(ProfileKeys.continueAction),
    matching: find.byType(FilledButton),
  ),
);

void main() {
  testWidgets('saves the profile and estimates the max heart rate', (
    tester,
  ) async {
    final store = await _pump(tester);
    expect(_text(tester, ProfileKeys.steps), '8000');

    await _type(tester, ProfileKeys.age, '36');
    expect(_text(tester, ProfileKeys.maxHeartRate), '184');
    await _type(tester, ProfileKeys.height, '172');
    await _type(tester, ProfileKeys.weight, '68,5');
    await tapAndSettle(tester, find.byKey(ProfileKeys.sex(Sex.female)));
    await tapAndSettle(tester, find.byKey(ProfileKeys.continueAction));

    expect(
      store.profile,
      const UserProfile(
        birthYear: 1990,
        sex: Sex.female,
        heightCentimeters: 172,
        weightKilograms: 68.5,
        dailyStepGoal: 8000,
      ),
    );
    expect(find.byType(HealthPermissionScreen), findsOneWidget);
  });

  testWidgets('a value out of range explains the range and blocks saving', (
    tester,
  ) async {
    final store = await _pump(tester);

    await _type(tester, ProfileKeys.height, '20');

    expect(find.text('Enter a value from 100 to 230.'), findsOneWidget);
    expect(_continue(tester).onPressed, isNull);

    await _type(tester, ProfileKeys.height, '180');

    expect(find.text('Enter a value from 100 to 230.'), findsNothing);
    expect(_continue(tester).onPressed, isNotNull);
    expect(store.profile, isNull);
  });

  testWidgets('a typed max heart rate is kept and can be reset', (
    tester,
  ) async {
    final store = await _pump(tester);
    await _type(tester, ProfileKeys.age, '40');

    await _type(tester, ProfileKeys.maxHeartRate, '191');
    expect(find.byKey(ProfileKeys.resetMaxHeartRate), findsOneWidget);
    await _type(tester, ProfileKeys.age, '30');
    expect(_text(tester, ProfileKeys.maxHeartRate), '191');

    await tapAndSettle(tester, find.byKey(ProfileKeys.resetMaxHeartRate));
    expect(_text(tester, ProfileKeys.maxHeartRate), '190');
    await _type(tester, ProfileKeys.maxHeartRate, '195');
    await tapAndSettle(tester, find.byKey(ProfileKeys.continueAction));

    expect(store.profile?.maxHeartRate, 195);
    expect(store.profile?.birthYear, 1996);
  });

  testWidgets('a saved profile fills the form', (tester) async {
    await _pump(
      tester,
      const UserProfile(
        birthYear: 1986,
        sex: Sex.male,
        heightCentimeters: 181,
        weightKilograms: 79.5,
        maxHeartRate: 186,
        dailyStepGoal: 10000,
      ),
    );

    expect(_text(tester, ProfileKeys.age), '40');
    expect(_text(tester, ProfileKeys.height), '181');
    expect(_text(tester, ProfileKeys.weight), '79.5');
    expect(_text(tester, ProfileKeys.maxHeartRate), '186');
    expect(_text(tester, ProfileKeys.steps), '10000');
    expect(
      tester.widget<ChoiceChip>(find.byKey(ProfileKeys.sex(Sex.male))).selected,
      isTrue,
    );
  });

  testWidgets('skipping moves on without saving', (tester) async {
    final store = await _pump(tester);
    await _type(tester, ProfileKeys.age, '36');

    await tapAndSettle(tester, find.byKey(ProfileKeys.skip));

    expect(store.profile, isNull);
    expect(find.byType(HealthPermissionScreen), findsOneWidget);
  });
}
