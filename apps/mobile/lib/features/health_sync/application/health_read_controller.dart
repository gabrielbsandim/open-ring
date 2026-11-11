import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meta/meta.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/application/import_external_sleep.dart';
import 'package:open_ring/features/health_sync/application/import_external_workouts.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

final healthReaderProvider = Provider<HealthReader>(
  (ref) => const UnavailableHealthReader(),
);

final healthReadStoreProvider = Provider<HealthReadStore>(
  (ref) => InMemoryHealthReadStore(),
);

final importExternalSleepProvider = Provider<ImportExternalSleep>(
  (ref) => ImportExternalSleep(
    reader: ref.watch(healthReaderProvider),
    store: ref.watch(healthReadStoreProvider),
    clock: ref.watch(clockProvider),
  ),
);

final importExternalWorkoutsProvider = Provider<ImportExternalWorkouts>(
  (ref) => ImportExternalWorkouts(
    reader: ref.watch(healthReaderProvider),
    store: ref.watch(healthReadStoreProvider),
    clock: ref.watch(clockProvider),
  ),
);

@immutable
final class HealthReadView {
  new({
    required this.enabled,
    required this.access,
    required List<ExternalSource> sources,
    required List<String> priority,
    this.lastReadAt,
    this.declined = false,
  }) : sources = List.unmodifiable(sources),
       priority = List.unmodifiable(priority);

  final bool enabled;
  final HealthAccess access;
  final List<ExternalSource> sources;
  final List<String> priority;
  final DateTime? lastReadAt;
  final bool declined;

  bool get single => priority.length < 2;

  ExternalSource? source(String id) {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  HealthReadView withPriority(List<String> order) => HealthReadView(
    enabled: enabled,
    access: access,
    sources: sources,
    priority: order,
    lastReadAt: lastReadAt,
    declined: declined,
  );
}

final AsyncNotifierProviderFamily<
  HealthReadController,
  HealthReadView,
  HealthRecordKind
>
healthReadsProvider =
    AsyncNotifierProvider.family<
      HealthReadController,
      HealthReadView,
      HealthRecordKind
    >(HealthReadController.new);

final AsyncNotifierProvider<HealthReadController, HealthReadView>
healthReadProvider = healthReadsProvider(HealthRecordKind.sleep);

final AsyncNotifierProvider<HealthReadController, HealthReadView>
workoutReadProvider = healthReadsProvider(HealthRecordKind.workout);

class HealthReadController extends AsyncNotifier<HealthReadView> {
  new(this._kind);

  final HealthRecordKind _kind;

  Future<void>? _importing;

  HealthReadStore get _store => ref.read(healthReadStoreProvider);

  HealthReader get _reader => ref.read(healthReaderProvider);

  @override
  Future<HealthReadView> build() {
    ref
      ..watch(healthReadStoreProvider)
      ..watch(healthReaderProvider);
    return _load();
  }

  Future<HealthReadView> _load({bool declined = false}) async {
    final (settings, access, sources, stored) = await (
      _store.settings(_kind),
      _reader.readAccess(_kind),
      _store.sources(_kind),
      _store.storedPriority(_kind),
    ).wait;
    final priority = settings.enabled
        ? resolveSourcePriority(stored, [for (final s in sources) s.id])
        : const [ringSource];
    return HealthReadView(
      enabled: settings.enabled,
      access: access,
      sources: sources,
      priority: priority,
      lastReadAt: settings.lastReadAt,
      declined: declined,
    );
  }

  Future<void> setEnabled({required bool enabled}) async {
    final granted = !enabled || await _grant();
    if (granted) await _store.setEnabled(_kind, enabled: enabled);
    await _reload(changed: granted, declined: !granted);
    if (enabled && granted) await importNow();
  }

  Future<bool> _grant() async {
    if (await _reader.readAccess(_kind) == HealthAccess.granted) return true;
    return await _reader.requestReadAccess(_kind);
  }

  Future<void> move(int from, int to) async {
    final view = state.value;
    if (view == null) return;
    final next = moveSource(view.priority, from, to);
    if (identical(next, view.priority)) return;
    state = AsyncData(view.withPriority(next));
    await _store.savePriority(_kind, next);
    if (!ref.mounted) return;
    ref.read(dataRevisionProvider.notifier).bump();
  }

  Future<void> importNow() =>
      _importing ??= _import().whenComplete(() => _importing = null);

  // A failed import never surfaces past the screen: the next sync retries.
  Future<void> _import() async {
    try {
      final report = await _importer();
      await _reload(changed: report.outcome == ImportOutcome.imported);
    } on Object {
      return;
    }
  }

  ExternalImport get _importer => switch (_kind) {
    HealthRecordKind.workout => ref.read(importExternalWorkoutsProvider),
    _ => ref.read(importExternalSleepProvider),
  };

  Future<void> _reload({required bool changed, bool declined = false}) async {
    if (!ref.mounted) return;
    final view = await _load(declined: declined);
    if (!ref.mounted) return;
    state = AsyncData(view);
    if (changed) ref.read(dataRevisionProvider.notifier).bump();
  }
}
