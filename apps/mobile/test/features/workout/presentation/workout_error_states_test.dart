import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/presentation/location_permission_screen.dart';
import 'package:open_ring/features/workout/presentation/recent_workouts_card.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/protocol_lab_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/workout_fakes.dart';
import 'workout_scenarios.dart';

final class _UnreadableHistory implements WorkoutStore, WorkoutHistoryReader {
  @override
  Future<List<WorkoutListItem>> recent({required int limit}) async =>
      throw const FileSystemException('database is locked');

  @override
  Future<SavedWorkout?> byId(int id) async => null;

  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) async => 1;

  @override
  Future<bool> delete(int id) async => false;
}

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

Future<void> _pumpApp(WidgetTester tester, WorkoutRig rig) async {
  await pumpScaled(
    tester,
    const OpenRingApp(),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    size: tallPhone,
    overrides: [
      ...protocolLabOverrides(),
      ...ringOverrides(),
      ...rig.overrides(),
      ringStatusReaderProvider.overrideWithValue(
        FakeRingStatusReader(pairedRing),
      ),
    ],
  );
  await tester.tap(
    find.byKey(AppNavigationBar.destinationKey(AppTab.activity)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a location status the phone cannot report opens the explainer', (
    tester,
  ) async {
    final rig = WorkoutRig()..access.fail = true;
    await _pumpApp(tester, rig);

    await _tap(tester, WorkoutEntryButton.startKey);
    await _tap(tester, WorkoutPickKeys.start);

    expect(find.byType(LocationPermissionScreen), findsOneWidget);
    expect(find.byKey(LocationPermissionKeys.allow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed location request can be retried or skipped', (
    tester,
  ) async {
    final rig = WorkoutRig()..access.fail = true;
    await pumpWorkout(
      tester,
      const LocationPermissionScreen(type: WorkoutType.running),
      rig,
      size: tallPhone,
    );

    await _tap(tester, LocationPermissionKeys.allow);

    expect(find.byKey(LocationPermissionKeys.checkFailed), findsOneWidget);
    expect(find.text(_en.workoutLocationCheckFailedBody), findsOneWidget);
    expect(find.byKey(LocationPermissionKeys.withoutGps), findsOneWidget);
    expect(find.byKey(LocationPermissionKeys.allow), findsNothing);

    rig.access.fail = false;
    await _tap(tester, LocationPermissionKeys.retry);

    expect(find.byKey(LocationPermissionKeys.checkFailed), findsNothing);
    expect(find.text(_en.workoutLocationGrantedTitle), findsOneWidget);
    expect(find.byKey(LocationPermissionKeys.start), findsOneWidget);
    expect(rig.access.current, LocationAccessStatus.granted);
    expect(tester.takeException(), isNull);
  });

  testWidgets('before asking it already offers to train without GPS', (
    tester,
  ) async {
    await pumpWorkout(
      tester,
      const LocationPermissionScreen(type: WorkoutType.running),
      WorkoutRig(),
      size: tallPhone,
    );

    expect(find.byKey(LocationPermissionKeys.allow), findsOneWidget);
    expect(find.byKey(LocationPermissionKeys.withoutGps), findsOneWidget);
  });

  testWidgets('recent workouts that cannot be read say so', (tester) async {
    await _pumpApp(tester, WorkoutRig(store: _UnreadableHistory()));

    await tester.scrollUntilVisible(
      find.byKey(RecentWorkoutsKeys.error),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(_en.metricLoadError), findsWidgets);
    expect(find.byKey(RecentWorkoutsKeys.empty), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no workouts yet points at the start button', (tester) async {
    await _pumpApp(tester, WorkoutRig());

    await tester.scrollUntilVisible(
      find.byKey(RecentWorkoutsKeys.empty),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(_en.workoutRecentEmptyHint(_en.workoutStart)),
      findsOneWidget,
    );
    expect(find.byKey(WorkoutEntryButton.startKey), findsOneWidget);
  });
}
