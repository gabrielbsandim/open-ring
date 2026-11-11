import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/application/export_providers.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/domain/file_sharer.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/settings/application/about_providers.dart';
import 'package:open_ring/features/settings/application/app_language_controller.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/features/settings/application/notification_providers.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/app_language.dart';
import 'package:open_ring/features/settings/domain/external_link_opener.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

import 'fake_health_writer.dart';
import 'layout_harness.dart';

final settingsNow = DateTime(2026, 11, 10, 9);

final class FakeOutboxSummaryReader implements OutboxSummaryReader {
  new([OutboxSummary? value]) : value = value ?? OutboxSummary();

  OutboxSummary value;

  @override
  Future<OutboxSummary> summary() async => value;
}

final class FakeHealthSettingsOpener implements HealthSettingsOpener {
  int opened = 0;

  @override
  Future<void> open() async => opened++;
}

final class RecordingExternalLinkOpener implements ExternalLinkOpener {
  final opened = <Uri>[];

  @override
  Future<void> open(Uri uri) async => opened.add(uri);
}

final class FakeLocalDataEraser implements LocalDataEraser {
  new({this.fail = false, this.hold});

  final bool fail;
  final Completer<void>? hold;
  int erased = 0;

  @override
  Future<void> eraseAll() async {
    await hold?.future;
    if (fail) throw const FileSystemException('disk full');
    erased++;
  }
}

final class FailingUserProfileStore implements UserProfileStore {
  new({this.failRead = false, this.profile});

  final bool failRead;
  final UserProfile? profile;
  int saves = 0;

  @override
  Future<UserProfile?> read() async {
    if (failRead) throw const FileSystemException('database is locked');
    return profile;
  }

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) async {
    saves++;
    throw const FileSystemException('disk full');
  }
}

class RecordingHealthSyncController extends HealthSyncController {
  new({this.seed, this.grant = false});

  final HealthSyncState? seed;
  final bool grant;
  int processed = 0;
  int requested = 0;

  @override
  HealthSyncState build() => seed ?? HealthSyncState();

  @override
  Future<void> process() async => processed++;

  @override
  Future<bool> requestAccess() async {
    requested++;
    return grant;
  }
}

final class FakeFileSharer implements FileSharer {
  final List<List<ExportFile>> shared = [];
  bool fail = false;

  @override
  Future<void> share(List<ExportFile> files, {required String subject}) async {
    if (fail) throw const FileShareException('no share sheet');
    shared.add(files);
  }
}

final class FakeDataExporter implements DataExporter {
  new({this.fail = false, this.hold});

  final bool fail;
  final Completer<void>? hold;
  final List<ExportRequest> requests = [];

  @override
  Future<ExportResult> export(ExportRequest request) async {
    requests.add(request);
    await hold?.future;
    if (fail) throw StateError('disk full');
    return sampleExportResult(request.format);
  }

  @override
  Future<ExportFile> exportRoute(WorkoutRoute route) =>
      throw UnimplementedError();

  @override
  Future<ExportFile> exportWorkoutCsv(
    FinishedWorkout workout, {
    required Duration offset,
  }) => throw UnimplementedError();
}

ExportResult sampleExportResult([ExportFormat format = ExportFormat.csv]) =>
    ExportResult(
      files: [
        switch (format) {
          ExportFormat.csv => const ExportFile(
            path: '/tmp/openring-export-1/openring-csv-20261110-090000.zip',
            mimeType: ExportFile.zipMimeType,
          ),
          ExportFormat.json => const ExportFile(
            path: '/tmp/openring-export-1/openring-20261110-090000.json',
            mimeType: ExportFile.jsonMimeType,
          ),
        },
      ],
      counts: const {ExportKind.heartRate: 12840, ExportKind.sleep: 312},
    );

class SeededExportController extends ExportController {
  new(this.seed);

  final ExportState seed;

  @override
  ExportState build() => seed;
}

const fullProfile = UserProfile(
  birthYear: 1992,
  sex: Sex.female,
  heightCentimeters: 178,
  weightKilograms: 76.5,
  dailyStepGoal: 12000,
);

final OutboxSummary deniedOutbox = OutboxSummary(
  pendingRecords: const {
    HealthRecordKind.heartRate: 241,
    HealthRecordKind.activity: 48,
    HealthRecordKind.spo2: 18,
    HealthRecordKind.sleep: 2,
    HealthRecordKind.workout: 1,
  },
  pendingRows: 9,
  oldestPendingAt: settingsNow.subtract(const Duration(minutes: 48)),
  lastSentAt: settingsNow.subtract(const Duration(days: 2)),
);

List<Override> settingsOverrides({
  FakeHealthWriter? writer,
  FakeOutboxSummaryReader? outbox,
  FakeHealthSettingsOpener? opener,
  RecordingHealthSyncController? health,
  FakeDataExporter? exporter,
  FakeFileSharer? sharer,
  ExportState? export,
  UserProfileStore? profiles,
  UnitSystemStore? units,
  AppLanguageStore? languages,
  NotificationAccess? notifications,
  LocalDataEraser? eraser,
  ExternalLinkOpener? links,
  String appVersion = '1.4.2',
}) => [
  clockProvider.overrideWithValue(() => settingsNow),
  appVersionProvider.overrideWith((ref) async => appVersion),
  externalLinkOpenerProvider.overrideWithValue(
    links ?? RecordingExternalLinkOpener(),
  ),
  healthWriterProvider.overrideWithValue(writer ?? FakeHealthWriter()),
  outboxSummaryReaderProvider.overrideWithValue(
    outbox ?? FakeOutboxSummaryReader(),
  ),
  healthSettingsOpenerProvider.overrideWithValue(
    opener ?? FakeHealthSettingsOpener(),
  ),
  healthSyncProvider.overrideWith(
    () => health ?? RecordingHealthSyncController(),
  ),
  dataExporterProvider.overrideWithValue(exporter ?? FakeDataExporter()),
  fileSharerProvider.overrideWithValue(sharer ?? FakeFileSharer()),
  if (export != null)
    exportProvider.overrideWith(() => SeededExportController(export)),
  userProfileStoreProvider.overrideWithValue(
    profiles ?? InMemoryUserProfileStore(),
  ),
  unitSystemStoreProvider.overrideWithValue(units ?? InMemoryUnitSystemStore()),
  appLanguageStoreProvider.overrideWithValue(
    languages ?? InMemoryAppLanguageStore(),
  ),
  notificationAccessProvider.overrideWithValue(
    notifications ?? InMemoryNotificationAccess(),
  ),
  localDataEraserProvider.overrideWithValue(eraser ?? FakeLocalDataEraser()),
];

// ListView builds only what is near the viewport, so a layout check has to
// scroll to the end to see every row.
Future<void> scrollThrough(WidgetTester tester) =>
    expectNoLayoutOverflow(() async {
      final scrollable = find.byType(Scrollable).first;
      for (var step = 0; step < 60; step++) {
        final position = tester.state<ScrollableState>(scrollable).position;
        if (position.pixels >= position.maxScrollExtent) return;
        position.jumpTo(
          math.min(
            position.pixels + position.viewportDimension * 0.8,
            position.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
      }
    });

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
