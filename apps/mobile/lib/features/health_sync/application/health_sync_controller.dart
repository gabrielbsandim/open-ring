import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/process_health_outbox.dart';
import 'package:open_ring/features/health_sync/domain/health_write_preferences.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_record_source.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';

final healthWriterProvider = Provider<HealthWriter>(
  (ref) => throw UnimplementedError('Override healthWriterProvider.'),
);

final healthWritePreferencesProvider = Provider<HealthWritePreferences>(
  (ref) => InMemoryHealthWritePreferences(),
);

ProcessHealthOutbox healthOutboxProcessor({
  required AppDatabase database,
  required HealthWriter writer,
  required HealthWritePreferences writes,
  required DateTime Function() clock,
}) => ProcessHealthOutbox(
  outbox: HealthOutboxDao(database),
  source: DriftHealthRecordSource(database),
  writer: writer,
  writes: writes,
  lock: SyncLocksDao(database, name: SyncLocksDao.healthOutbox),
  clock: clock,
);

final processHealthOutboxProvider = Provider<ProcessHealthOutbox>(
  (ref) => healthOutboxProcessor(
    database: ref.watch(appDatabaseProvider),
    writer: ref.watch(healthWriterProvider),
    writes: ref.watch(healthWritePreferencesProvider),
    clock: ref.watch(clockProvider),
  ),
);

final Set<HealthRecordKind> writableHealthKinds = {
  for (final kind in HealthRecordKind.values)
    if (kind.hasPlatformType) kind,
};

@immutable
final class HealthSyncState {
  new({
    this.running = false,
    this.lastRunAt,
    Set<HealthRecordKind> denied = const {},
    this.unavailable = false,
    this.dead = 0,
    this.lastError,
  }) : denied = Set.unmodifiable(denied);

  final bool running;
  final DateTime? lastRunAt;
  final Set<HealthRecordKind> denied;
  final bool unavailable;
  final int dead;
  final String? lastError;

  bool get blocked => unavailable || denied.isNotEmpty;

  HealthSyncState started() => HealthSyncState(
    running: true,
    lastRunAt: lastRunAt,
    denied: denied,
    unavailable: unavailable,
    dead: dead,
  );

  HealthSyncState finished(HealthOutboxReport report, DateTime at) {
    if (report.busy) return idle();
    return HealthSyncState(
      lastRunAt: at,
      denied: report.denied,
      unavailable: report.unavailable,
      dead: report.dead,
    );
  }

  HealthSyncState failed(String error) => HealthSyncState(
    lastRunAt: lastRunAt,
    denied: denied,
    unavailable: unavailable,
    dead: dead,
    lastError: error,
  );

  HealthSyncState idle() => HealthSyncState(
    lastRunAt: lastRunAt,
    denied: denied,
    unavailable: unavailable,
    dead: dead,
  );
}

final healthSyncProvider =
    NotifierProvider<HealthSyncController, HealthSyncState>(
      HealthSyncController.new,
    );

class HealthSyncController extends Notifier<HealthSyncState> {
  Future<void>? _running;

  @override
  HealthSyncState build() => HealthSyncState();

  Future<void> process() =>
      _running ??= _process().whenComplete(() => _running = null);

  Future<bool> requestAccess() async {
    final granted = await ref
        .read(healthWriterProvider)
        .requestAccess(writableHealthKinds);
    if (granted) await process();
    return granted;
  }

  Future<void> _process() async {
    state = state.started();
    try {
      final report = await ref.read(processHealthOutboxProvider)();
      if (!ref.mounted) return;
      state = state.finished(report, ref.read(clockProvider)());
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = state.failed('$error');
    }
  }
}
