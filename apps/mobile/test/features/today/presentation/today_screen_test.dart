import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/presentation/readiness_screen.dart';
import 'package:open_ring/features/today/presentation/today_cards.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_entry_button.dart';
import 'package:open_ring/features/workout/presentation/workout_pick_screen.dart';

import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';
import '../../../helpers/metrics_pump.dart';
import '../../../helpers/rem_reporting_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

List<Override> _offline(FakeRingDriver driver) => metricsOverrides(
  offlineScenario,
  ring: ringOverrides(
    paired: offlineScenario.pairedRing,
    driver: driver,
    clock: () => metricsNow,
  ),
);

FakeRingDriver _unreachable() =>
    FakeRingDriver()..connectError = Exception('out of range');

Future<void> _tapSync(WidgetTester tester) async {
  await reveal(tester, find.byKey(TodayKeys.offlineAction));
  await expectNoLayoutOverflow(() async {
    await tester.tap(find.byKey(TodayKeys.offlineAction));
    await tester.pumpAndSettle();
  });
}

void main() {
  testWidgets('without a ring it says to pair one', (tester) async {
    await pumpMetrics(tester, screenHost(const TodayScreen()), noDataScenario);

    expect(find.text('No ring paired'), findsOneWidget);
    expect(find.textContaining('Pair your ring to see'), findsOneWidget);
    expect(find.byKey(TodayKeys.pairAction), findsOneWidget);
    expect(find.byKey(TodayKeys.readiness), findsNothing);
  });

  group('without a ring and with a read on', () {
    Future<void> pumpUnpaired(
      WidgetTester tester, {
      required int nights,
      bool sleepRead = true,
    }) async {
      final store = InMemoryHealthReadStore();
      if (sleepRead) {
        await store.setEnabled(HealthRecordKind.sleep, enabled: true);
      }
      await pumpScaled(
        tester,
        screenHost(const TodayScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          ...metricsOverrides(
            MetricsScenario(
              nights: nights,
              activityDays: 0,
              ring: RingStatus.unpaired,
            ),
          ),
          healthReadStoreProvider.overrideWithValue(store),
          healthReaderProvider.overrideWithValue(
            FakeHealthReader(access: HealthAccess.granted),
          ),
        ],
      );
    }

    testWidgets('an imported night shows the sleep card and the pair entry', (
      tester,
    ) async {
      await pumpUnpaired(tester, nights: 1);

      expect(find.byKey(TodayKeys.sleep), findsOneWidget);
      expect(find.byKey(TodayKeys.pairAction), findsOneWidget);
      expect(
        find.text('Pair a ring to add steps, heart rate and readiness.'),
        findsOneWidget,
      );
      expect(find.byKey(TodayKeys.readiness), findsNothing);
      expect(find.textContaining('Pair your ring to see'), findsNothing);
    });

    testWidgets('with no night yet the sleep card says so', (tester) async {
      await pumpUnpaired(tester, nights: 0);

      expect(find.byKey(TodayKeys.sleep), findsOneWidget);
      expect(find.text('No night from Health Connect yet.'), findsOneWidget);
      expect(find.byKey(TodayKeys.pairAction), findsOneWidget);
      expect(find.byKey(TodayKeys.readiness), findsNothing);
    });

    testWidgets('with the reads off Today stays the empty pair card', (
      tester,
    ) async {
      await pumpUnpaired(tester, nights: 1, sleepRead: false);

      expect(
        find.text("Pair your ring to see today's steps, heart rate and sleep."),
        findsOneWidget,
      );
      expect(find.byKey(TodayKeys.sleep), findsNothing);
      expect(find.byKey(TodayKeys.pairAction), findsOneWidget);
    });
  });

  testWidgets('with full data shows every summary card', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const TodayScreen()),
      fullDataScenario,
    );

    expect(find.text('Synced 08:40 · 68%'), findsOneWidget);
    expect(find.text('Tue, Nov 10'), findsOneWidget);
    expect(find.byKey(TodayKeys.readiness), findsOneWidget);
    expect(find.byKey(TodayKeys.offline), findsNothing);
    expect(find.text('6 h 52 min'), findsOneWidget);
    expect(find.text('score 95'), findsOneWidget);
    expect(find.text('23:18 to 06:42'), findsOneWidget);
    expect(find.text('2,224'), findsOneWidget);
    expect(find.text('of 8,000 steps'), findsOneWidget);
    expect(find.text('87 kcal · 1.54 km'), findsOneWidget);
    expect(
      find.textContaining('Compared with your baseline of 27'),
      findsOneWidget,
    );
    expect(find.byKey(TodayKeys.staleMarker), findsNothing);
  });

  testWidgets('the sync status sits to the right of the title', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const TodayScreen()),
      fullDataScenario,
    );
    tester.view
      ..physicalSize = const Size(1000, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    final title = tester.getCenter(find.text('Today'));
    final chip = tester.getCenter(find.byKey(TodayKeys.syncChip));

    expect(chip.dy, moreOrLessEquals(title.dy, epsilon: 1));
    expect(chip.dx, greaterThan(title.dx));
  });

  testWidgets('offline says since when, why and what to do', (tester) async {
    await pumpMetrics(tester, screenHost(const TodayScreen()), offlineScenario);

    expect(find.byKey(TodayKeys.offline), findsOneWidget);
    expect(find.text('Ring not synced since 00:00'), findsOneWidget);
    expect(find.text('Not synced for 9 hours'), findsOneWidget);
    expect(find.textContaining('battery was at 14%'), findsOneWidget);
    expect(find.byKey(TodayKeys.offlineAction), findsOneWidget);
    expect(find.byKey(TodayKeys.staleMarker), findsNWidgets(2));
    expect(find.text("Last night is complete and won't change"), findsNothing);
  });

  testWidgets('offline after the night ended says it will not change', (
    tester,
  ) async {
    await pumpMetrics(
      tester,
      screenHost(const TodayScreen()),
      MetricsScenario(
        nights: 28,
        activityDays: 29,
        now: metricsNow.add(const Duration(hours: 5)),
        ring: RingStatus(
          paired: true,
          name: 'R09_C0FE',
          model: 'R09',
          lastSyncAt: metricsNow.subtract(const Duration(hours: 1)),
          batteryPercent: 14,
        ),
      ),
    );

    expect(find.byKey(TodayKeys.offline), findsOneWidget);
    expect(
      find.text("Last night is complete and won't change"),
      findsOneWidget,
    );
  });

  testWidgets('while the baseline builds it counts the nights', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const TodayScreen()),
      buildingScenario,
    );

    expect(find.text('Learning your baseline: 2 of 7 nights.'), findsOneWidget);
  });

  testWidgets('the readiness card opens the readiness inputs', (tester) async {
    await pumpMetrics(tester, const OpenRingApp(), fullDataScenario);
    await tester.ensureVisible(find.byKey(TodayKeys.readiness));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TodayKeys.readiness));
    await tester.pumpAndSettle();

    expect(find.byType(ReadinessScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('the sleep card opens the Sleep tab', (tester) async {
    await pumpMetrics(tester, const OpenRingApp(), fullDataScenario);
    await tester.ensureVisible(find.byKey(TodayKeys.sleep));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(TodayKeys.sleep));
    await tester.pumpAndSettle();

    expect(find.byType(SleepScreen), findsOneWidget);
  });

  testWidgets('with a score the card names its band', (tester) async {
    await pumpMetrics(
      tester,
      screenHost(const TodayScreen()),
      fullDataScenario,
    );

    expect(
      find.descendant(
        of: find.byKey(TodayKeys.readiness),
        matching: find.textContaining(
          RegExp(r'^(Optimal|Good|Fair|Low) readiness$'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Start workout opens the workout picker', (tester) async {
    await pumpMetrics(tester, const OpenRingApp(), fullDataScenario);
    await reveal(tester, find.byKey(WorkoutEntryButton.startKey));
    expect(find.byKey(TodayKeys.workoutNote), findsNothing);

    await tester.tap(find.byKey(WorkoutEntryButton.startKey));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutPickScreen), findsOneWidget);
  });

  testWidgets('offline warns that the workout needs the ring', (tester) async {
    await pumpMetrics(tester, screenHost(const TodayScreen()), offlineScenario);

    await reveal(tester, find.byKey(TodayKeys.workoutNote));
    expect(find.byKey(WorkoutEntryButton.startKey), findsOneWidget);
    expect(find.textContaining('needs the ring nearby'), findsOneWidget);
  });

  testWidgets('Sync now starts a sync on the ring', (tester) async {
    final driver = FakeRingDriver();
    await pumpScaled(
      tester,
      screenHost(const TodayScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: _offline(driver),
    );
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.byKey(TodayKeys.offlineTried), findsNothing);

    await _tapSync(tester);

    expect(driver.connects, 1);
  });

  testWidgets('a failed sync says when it was tried and offers a retry', (
    tester,
  ) async {
    final driver = _unreachable();
    await pumpScaled(
      tester,
      screenHost(const TodayScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: _offline(driver),
    );

    await _tapSync(tester);

    expect(
      find.text(
        'Last try at 09:00. Could not reach the ring. '
        'Keep it close to this phone and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
    expect(find.byKey(SyncKeys.error), findsNothing);

    await _tapSync(tester);
    expect(driver.connects, 2);
  });

  testWidgets('What to do opens the Ring tab', (tester) async {
    await pumpMetrics(tester, const OpenRingApp(), offlineScenario);
    await reveal(tester, find.byKey(TodayKeys.offlineHelp));

    await tester.tap(find.byKey(TodayKeys.offlineHelp));
    await tester.pumpAndSettle();

    expect(find.byType(RingScreen), findsOneWidget);
  });

  for (final c in layoutMatrix()) {
    testWidgets('the workout button lays out at $c', (tester) async {
      await pumpScaled(
        tester,
        screenHost(const TodayScreen()),
        textScaler: c.textScaler,
        brightness: c.brightness,
        locale: c.locale,
        overrides: metricsOverrides(fullDataScenario),
      );

      await reveal(tester, find.byKey(WorkoutEntryButton.startKey));
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the offline card after a failed sync lays out at $c', (
      tester,
    ) async {
      await pumpScaled(
        tester,
        screenHost(const TodayScreen()),
        textScaler: c.textScaler,
        brightness: c.brightness,
        locale: c.locale,
        overrides: _offline(_unreachable()),
      );

      await _tapSync(tester);
      await reveal(tester, find.byKey(TodayKeys.offlineTried));
      expect(find.byKey(TodayKeys.offlineHelp), findsOneWidget);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final c in layoutMatrix()) {
    testWidgets('imperial units show the activity distance in miles at $c', (
      tester,
    ) async {
      await pumpScaled(
        tester,
        screenHost(const TodayScreen()),
        textScaler: c.textScaler,
        brightness: c.brightness,
        locale: c.locale,
        overrides: [
          ...metricsOverrides(fullDataScenario),
          unitSystemStoreProvider.overrideWithValue(
            InMemoryUnitSystemStore(UnitSystem.imperial),
          ),
        ],
      );

      final miles = c.locale.languageCode == 'de' ? '0,96' : '0.96';
      await tester.scrollUntilVisible(
        find.byKey(TodayKeys.activity),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: find.byKey(TodayKeys.activity),
          matching: find.text('87 kcal · $miles mi'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(' km'), findsNothing);
    });
  }

  group('a ring that does not report REM', () {
    Finder inSleepCard(Finder matching) =>
        find.descendant(of: find.byKey(TodayKeys.sleep), matching: matching);

    for (final c in layoutMatrix()) {
      testWidgets('the sleep card legend has no REM at $c', (tester) async {
        await pumpScaled(
          tester,
          screenHost(const TodayScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: todayWithoutRemOverrides(),
        );

        expect(find.byKey(TodayKeys.sleep), findsOneWidget);
        expect(inSleepCard(find.textContaining(RegExp('^REM'))), findsNothing);
        expect(
          inSleepCard(find.textContaining(RegExp('^Light|^Leicht'))),
          findsOneWidget,
        );
        await scrollThrough(tester);
      });
    }

    testWidgets('the sleep bar does not announce REM', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScaled(
        tester,
        screenHost(const TodayScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: todayWithoutRemOverrides(),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'deep [^,]+, awake [^.]+\.$')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('keeps REM while the ring is still being judged', (
      tester,
    ) async {
      await pumpScaled(
        tester,
        screenHost(const TodayScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: todayWithoutRemOverrides(reporting: RemReporting.unknown),
      );

      expect(inSleepCard(find.textContaining(RegExp('^REM '))), findsOneWidget);
    });
  });
}
