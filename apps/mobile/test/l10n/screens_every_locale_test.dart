import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/activity/presentation/activity_screen.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/presentation/export_screen.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/presentation/health_status_screen.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:open_ring/features/heart/domain/heart_history_reader.dart';
import 'package:open_ring/features/heart/presentation/heart_screen.dart';
import 'package:open_ring/features/heart/presentation/measure_screen.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/presentation/first_sync_screen.dart';
import 'package:open_ring/features/onboarding/presentation/health_permission_screen.dart';
import 'package:open_ring/features/onboarding/presentation/permissions_screen.dart';
import 'package:open_ring/features/onboarding/presentation/profile_screen.dart';
import 'package:open_ring/features/onboarding/presentation/welcome_screen.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/presentation/pair_error_screen.dart';
import 'package:open_ring/features/ring/presentation/pair_screen.dart';
import 'package:open_ring/features/ring/presentation/protocol_lab_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/settings/presentation/data_sources_screen.dart';
import 'package:open_ring/features/settings/presentation/privacy_policy_screen.dart';
import 'package:open_ring/features/settings/presentation/profile_editor.dart';
import 'package:open_ring/features/settings/presentation/profile_section.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/domain/sleep_history_reader.dart';
import 'package:open_ring/features/sleep/presentation/sleep_screen.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';
import 'package:open_ring/features/today/presentation/formula_screen.dart';
import 'package:open_ring/features/today/presentation/readiness_screen.dart';
import 'package:open_ring/features/today/presentation/today_cards.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/features/trends/presentation/trends_screen.dart';
import 'package:open_ring/features/widgets/application/widget_providers.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_config_screen.dart';
import 'package:open_ring/features/widgets/presentation/widgets_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../helpers/fake_health_reader.dart';
import '../helpers/fake_health_writer.dart';
import '../helpers/layout_harness.dart';
import '../helpers/metrics_fakes.dart';
import '../helpers/metrics_pump.dart';
import '../helpers/onboarding_app.dart';
import '../helpers/onboarding_fakes.dart';
import '../helpers/protocol_lab_fakes.dart';
import '../helpers/ring_fakes.dart';
import '../helpers/settings_fakes.dart';
import '../helpers/widget_fakes.dart';

const _readFailure = FileSystemException('database is locked');

final class _FailingSleepReader implements SleepHistoryReader {
  @override
  Future<List<SleepSpan>> sleepSpans({
    required DateTime from,
    required DateTime to,
  }) async => throw _readFailure;
}

final class _FailingHeartReader implements HeartHistoryReader {
  @override
  Future<List<BpmSample>> heartRate({
    required DateTime from,
    required DateTime to,
  }) async => throw _readFailure;

  @override
  Future<List<HrvReading>> hrv({
    required DateTime from,
    required DateTime to,
  }) async => throw _readFailure;

  @override
  Future<List<Spo2Reading>> spo2({
    required DateTime from,
    required DateTime to,
  }) async => throw _readFailure;

  @override
  Future<List<StressReading>> stress({
    required DateTime from,
    required DateTime to,
  }) async => throw _readFailure;
}

final class _FailingActivityReader implements ActivityHistoryReader {
  @override
  Future<List<ActivitySlot>> activitySlots({
    required LocalDate from,
    required LocalDate to,
  }) async => throw _readFailure;

  @override
  Future<List<DailyActivity>> dailyActivity({
    required LocalDate from,
    required LocalDate to,
  }) async => throw _readFailure;
}

final class _FailingRingStatusReader implements RingStatusReader {
  @override
  Future<RingStatus> status() async => throw _readFailure;
}

typedef _Check = Future<void> Function(WidgetTester tester, AppLocalizations l);

final class _Case {
  const new(this.screen, this.overrides, {this.check});

  final Widget screen;
  final List<Override> Function() overrides;
  final _Check? check;
}

List<Override> _metrics(MetricsScenario scenario) => metricsOverrides(scenario);

List<Override> _readFailed() => [
  ...protocolLabOverrides(),
  ...ringOverrides(
    paired: fullDataScenario.pairedRing,
    clock: () => metricsNow,
  ),
  clockProvider.overrideWithValue(() => metricsNow),
  sleepHistoryReaderProvider.overrideWithValue(_FailingSleepReader()),
  heartHistoryReaderProvider.overrideWithValue(_FailingHeartReader()),
  activityHistoryReaderProvider.overrideWithValue(_FailingActivityReader()),
  ringStatusReaderProvider.overrideWithValue(_FailingRingStatusReader()),
];

List<Override> _withRing({
  MetricsScenario? scenario,
  RingSyncState? seed,
  MeasureState? measure,
}) {
  final data = scenario ?? fullDataScenario;
  return metricsOverrides(
    data,
    ring: ringOverrides(
      paired: data.pairedRing,
      seed: seed,
      measure: measure,
      clock: () => metricsNow,
    ),
  );
}

List<Override> _onboarding({
  PairState? pair,
  Map<AppPermission, PermissionStatus>? permissions,
  UserProfileStore? profiles,
}) => [
  ...protocolLabOverrides(),
  ...ringOverrides(),
  ...onboardingOverrides(
    permissions: FakeAppPermissions(statuses: permissions),
    profileStore: profiles,
    pairSeed: pair,
  ),
];

List<Override> _settings({
  UserProfileStore? profiles,
  NotificationAccess? notifications,
  FakeHealthWriter? writer,
  FakeOutboxSummaryReader? outbox,
  ExportState? export,
}) => [
  ...protocolLabOverrides(),
  ...ringOverrides(),
  ...settingsOverrides(
    profiles: profiles,
    notifications: notifications,
    writer: writer,
    outbox: outbox,
    export: export,
  ),
];

List<Override> _sources(MetricsScenario scenario) => [
  ...metricsOverrides(scenario),
  healthReaderProvider.overrideWithValue(FakeHealthReader()),
  healthReadStoreProvider.overrideWithValue(InMemoryHealthReadStore()),
  healthSettingsOpenerProvider.overrideWithValue(FakeHealthSettingsOpener()),
];

List<Override> _widgets({
  MetricsScenario? scenario,
  FakeWidgetGateway? gateway,
}) => [
  ...metricsOverrides(scenario ?? fullDataScenario),
  widgetGatewayProvider.overrideWithValue(gateway ?? FakeWidgetGateway()),
  todayWidgetConfigStoreProvider.overrideWithValue(
    InMemoryTodayWidgetConfigStore(),
  ),
];

Future<void> _expectText(WidgetTester tester, String text) async {
  await reveal(tester, find.text(text));
  expect(find.text(text), findsOneWidget);
}

Future<void> _expectLoadError(WidgetTester tester, AppLocalizations l) async =>
    expect(find.text(l.metricLoadError), findsWidgets);

Future<void> _tapRevealed(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await expectNoLayoutOverflow(() async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  });
}

const List<DiscoveredDevice> _rings = [colmiRing, bondedRing];

final _cases = <String, _Case>{
  'Welcome': const _Case(WelcomeScreen(), _onboarding),
  'Permissions before asking': const _Case(PermissionsScreen(), _onboarding),
  'Permissions with one blocked': _Case(
    const PermissionsScreen(),
    () => _onboarding(
      permissions: {
        AppPermission.bluetooth: PermissionStatus.granted,
        AppPermission.notifications: PermissionStatus.permanentlyDenied,
      },
    ),
  ),
  'Profile': const _Case(ProfileScreen(), _onboarding),
  'Profile that cannot be read': _Case(
    const ProfileScreen(),
    () => _onboarding(profiles: FailingUserProfileStore(failRead: true)),
    check: (tester, l) async {
      final age = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ProfileKeys.age),
          matching: find.byType(TextField),
        ),
      );
      expect(age.controller?.text, isEmpty);
    },
  ),
  'Profile that cannot be saved': _Case(
    const ProfileScreen(),
    () => _onboarding(profiles: FailingUserProfileStore()),
    check: (tester, l) async {
      await _tapRevealed(tester, find.byKey(ProfileKeys.continueAction));
      expect(find.byType(ProfileScreen), findsOneWidget);
      await _expectText(tester, l.profileSaveFailed);
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(ProfileKeys.continueAction),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    },
  ),
  'Health permission': const _Case(HealthPermissionScreen(), _onboarding),
  'Health permission connected': const _Case(
    HealthPermissionScreen(initialPhase: HealthConnectPhase.connected),
    _onboarding,
  ),
  'Health permission declined': const _Case(
    HealthPermissionScreen(initialPhase: HealthConnectPhase.declined),
    _onboarding,
  ),
  'Pair before searching': const _Case(
    PairScreen(flow: PairFlow.onboarding),
    _onboarding,
  ),
  'Pair while scanning': _Case(
    const PairScreen(flow: PairFlow.onboarding),
    () => _onboarding(
      pair: const PairState(
        phase: PairPhase.scanning,
        devices: _rings,
        scanActive: true,
      ),
    ),
  ),
  'Pair after a failed connection': _Case(
    const PairScreen(),
    () => _onboarding(
      pair: const PairState(
        phase: PairPhase.scanning,
        devices: _rings,
        target: colmiRing,
        connectFailed: true,
      ),
    ),
  ),
  'Pair whose pairing could not be saved': _Case(
    const PairScreen(),
    () => _onboarding(
      pair: const PairState(
        phase: PairPhase.scanning,
        devices: _rings,
        target: colmiRing,
        saveFailed: true,
      ),
    ),
    check: (tester, l) async {
      await reveal(tester, find.byKey(PairKeys.saveFailed));
      expect(find.text(l.pairSaveFailed(colmiRing.name)), findsOneWidget);
      expect(find.byKey(PairKeys.connectFailed), findsNothing);
    },
  ),
  for (final failure in PairFailure.values)
    'Pair error ${failure.name}': _Case(
      PairErrorScreen(failure: failure),
      _onboarding,
    ),
  'First sync that fails': const _Case(FirstSyncScreen(), _onboarding),
  for (final (name, screen) in const [
    ('Today', TodayScreen()),
    ('Readiness', ReadinessScreen()),
    ('Formula', FormulaScreen()),
    ('Sleep', SleepScreen()),
    ('Heart', HeartScreen()),
    ('Activity', ActivityScreen()),
    ('Trends', TrendsScreen()),
    ('Ring', RingScreen()),
  ]) ...{
    '$name with data': _Case(screen, () => _metrics(fullDataScenario)),
    '$name without a ring': _Case(screen, () => _metrics(noDataScenario)),
    '$name when stored data cannot be read': _Case(
      screen,
      _readFailed,
      check: _expectLoadError,
    ),
  },
  'Today offline': _Case(
    const TodayScreen(),
    () => _metrics(offlineScenario),
    check: (tester, l) async =>
        expect(find.byKey(TodayKeys.offline), findsOneWidget),
  ),
  'Today offline after a sync that could not reach the ring': _Case(
    const TodayScreen(),
    () => _withRing(
      scenario: offlineScenario,
      seed: const RingSyncState(
        lastError: SyncAborted(SyncStep.connecting, 'GATT_ERROR 133'),
      ),
    ),
    check: (tester, l) async {
      await reveal(tester, find.byKey(TodayKeys.offlineTried));
      expect(find.text(l.syncErrorConnecting), findsOneWidget);
    },
  ),
  'Ring offline': _Case(const RingScreen(), () => _metrics(offlineScenario)),
  'Ring after a sync that could not reach the ring': _Case(
    const RingScreen(),
    () => _withRing(
      seed: const RingSyncState(
        lastError: SyncAborted(SyncStep.connecting, 'GATT_ERROR 133'),
      ),
    ),
    check: (tester, l) async =>
        expect(find.textContaining('GATT_ERROR'), findsNothing),
  ),
  'Sleep without a night offers the Ring tab': _Case(
    const SleepScreen(),
    () => _metrics(noDataScenario),
    check: (tester, l) async {
      expect(find.byKey(SleepScreen.emptyActionKey), findsOneWidget);
      expect(find.text(l.metricOpenRing), findsOneWidget);
    },
  ),
  'Measure': _Case(const MeasureScreen(), () => _metrics(fullDataScenario)),
  for (final failure in MeasureFailure.values)
    'Measure failed with ${failure.name}': _Case(
      const MeasureScreen(),
      () => _withRing(
        scenario: failure == MeasureFailure.noRing ? noDataScenario : null,
        measure: MeasureState(phase: MeasurePhase.failed, failure: failure),
      ),
    ),
  'Settings': const _Case(SettingsScreen(), _settings),
  'Settings with notifications off': _Case(
    const SettingsScreen(),
    () => _settings(notifications: InMemoryNotificationAccess(allowed: false)),
  ),
  'Settings with a profile that cannot be read': _Case(
    const SettingsScreen(),
    () => _settings(profiles: FailingUserProfileStore(failRead: true)),
    check: (tester, l) async {
      await reveal(tester, find.byKey(ProfileSectionKeys.loadError));
      expect(find.text(l.profileLoadError), findsOneWidget);
      await tester.tap(find.byKey(ProfileSectionKeys.field(ProfileField.sex)));
      await tester.pumpAndSettle();
      expect(find.byKey(ProfileEditorKeys.sex(Sex.male)), findsNothing);
    },
  ),
  'Settings with a profile that cannot be saved': _Case(
    const SettingsScreen(),
    () => _settings(profiles: FailingUserProfileStore()),
    check: (tester, l) async {
      await _tapRevealed(
        tester,
        find.byKey(ProfileSectionKeys.field(ProfileField.sex)),
      );
      await expectNoLayoutOverflow(() async {
        await tester.tap(find.byKey(ProfileEditorKeys.sex(Sex.male)));
        await tester.pumpAndSettle();
      });
      expect(find.text(l.profileSaveFailed), findsOneWidget);
      expect(find.text(l.settingsNotSet), findsWidgets);
    },
  ),
  'Health status granted': const _Case(HealthStatusScreen(), _settings),
  'Health status denied': _Case(
    const HealthStatusScreen(),
    () => _settings(
      writer: FakeHealthWriter()..denied.addAll(writableHealthKinds),
      outbox: FakeOutboxSummaryReader(deniedOutbox),
    ),
  ),
  'Health status unavailable': _Case(
    const HealthStatusScreen(),
    () => _settings(writer: FakeHealthWriter()..unavailable = true),
  ),
  'Export': const _Case(ExportScreen(), _settings),
  'Privacy policy': const _Case(PrivacyPolicyScreen(), _settings),
  'Widgets without a ring': _Case(
    const WidgetsScreen(),
    () => _widgets(scenario: noDataScenario),
  ),
  'Export failed': _Case(
    const ExportScreen(),
    () => _settings(export: ExportState(phase: ExportPhase.failed)),
    check: (tester, l) => _expectText(tester, l.exportFailed),
  ),
  'Export that could not be shared': _Case(
    const ExportScreen(),
    () => _settings(
      export: ExportState(
        phase: ExportPhase.done,
        result: sampleExportResult(),
        shareFailed: true,
      ),
    ),
    check: (tester, l) => _expectText(tester, l.exportShareFailed),
  ),
  'Data sources': _Case(
    const DataSourcesScreen(),
    () => _sources(fullDataScenario),
  ),
  'Data sources without a ring': _Case(
    const DataSourcesScreen(),
    () => _sources(noDataScenario),
    check: (tester, l) async =>
        expect(find.text(l.sourcesRingUnpaired), findsOneWidget),
  ),
  'Widgets': const _Case(WidgetsScreen(), _widgets),
  'Today widget': const _Case(TodayWidgetConfigScreen(), _widgets),
  'Today widget without data': _Case(
    const TodayWidgetConfigScreen(),
    () => _widgets(scenario: noDataScenario),
  ),
  'Today widget the launcher does not add': _Case(
    const TodayWidgetConfigScreen(),
    () => _widgets(gateway: FakeWidgetGateway(pinFails: true)),
    check: (tester, l) async {
      await _tapRevealed(tester, find.byKey(TodayWidgetConfigScreen.addKey));
      await reveal(tester, find.byKey(TodayWidgetConfigScreen.pinFailedKey));
      expect(find.text(l.widgetPinFailed), findsOneWidget);
      expect(find.byKey(TodayWidgetConfigScreen.requestedKey), findsNothing);
      expect(find.byKey(TodayWidgetConfigScreen.addKey), findsOneWidget);
    },
  ),
  'Protocol lab': _Case(
    const ProtocolLabScreen(),
    () => [...protocolLabOverrides(), ...ringOverrides()],
  ),
};

Future<void> _pumpIn(WidgetTester tester, Locale locale, _Case c) => pumpScaled(
  tester,
  screenHost(c.screen),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: locale,
  overrides: c.overrides(),
);

void main() {
  test('the app ships 11 locales', () {
    expect(AppLocales.supported, hasLength(11));
  });

  for (final locale in AppLocales.supported) {
    group('$locale', () {
      final l10n = lookupAppLocalizations(locale);

      for (final MapEntry(key: name, value: c) in _cases.entries) {
        testWidgets('$name lays out without overflow or exception', (
          tester,
        ) async {
          await _pumpIn(tester, locale, c);
          expect(tester.takeException(), isNull);
          expect(find.byWidget(c.screen), findsOneWidget);

          await c.check?.call(tester, l10n);
          expect(tester.takeException(), isNull);

          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }

  testWidgets('the Sleep empty state leads to the Ring tab', (tester) async {
    await pumpMetrics(tester, const OpenRingApp(), noDataScenario);

    await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.sleep)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SleepScreen.emptyActionKey));
    await tester.pumpAndSettle();

    expect(find.byType(RingScreen), findsOneWidget);
    expect(find.byKey(RingScreen.pairKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed onboarding save can be retried and moves on', (
    tester,
  ) async {
    final store = _FlakyProfileStore();
    await pumpOnboardingApp(
      tester,
      at: AppPaths.onboardingProfile,
      overrides: _onboarding(profiles: store),
    );

    await tapAndSettle(tester, find.byKey(ProfileKeys.continueAction));
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byKey(ProfileKeys.saveFailed), findsOneWidget);

    store.fail = false;
    await tapAndSettle(tester, find.byKey(ProfileKeys.continueAction));

    expect(store.profile, isNotNull);
    expect(find.byType(HealthPermissionScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _FlakyProfileStore implements UserProfileStore {
  bool fail = true;
  UserProfile? profile;

  @override
  Future<UserProfile?> read() async => profile;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) async {
    if (fail) throw const FileSystemException('disk full');
    this.profile = profile;
  }
}
