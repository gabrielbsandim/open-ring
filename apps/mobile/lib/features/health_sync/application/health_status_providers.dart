import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/application/retry_dead_health_rows.dart';
import 'package:open_ring/features/health_sync/domain/health_outbox_store.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_outbox_summary_reader.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_health_settings_opener.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';

enum HealthConnection { connected, partial, denied, unavailable }

@immutable
final class HealthStatusView {
  new({
    required Map<HealthRecordKind, HealthAccess> access,
    required this.outbox,
    Set<HealthRecordKind> disabled = const {},
  }) : access = Map.unmodifiable(access),
       disabled = Set.unmodifiable(disabled);

  final Map<HealthRecordKind, HealthAccess> access;
  final OutboxSummary outbox;
  final Set<HealthRecordKind> disabled;

  HealthConnection get connection {
    final kept = [
      for (final MapEntry(key: kind, value: state) in access.entries)
        if (!disabled.contains(kind)) state,
    ];
    final values = kept.isEmpty ? access.values.toList() : kept;
    if (values.contains(HealthAccess.unavailable)) {
      return HealthConnection.unavailable;
    }
    final denied = values.where((value) => value == HealthAccess.denied);
    if (denied.isEmpty) return HealthConnection.connected;
    if (denied.length == values.length) return HealthConnection.denied;
    return HealthConnection.partial;
  }
}

final outboxSummaryReaderProvider = Provider<OutboxSummaryReader>(
  (ref) => DriftOutboxSummaryReader(ref.watch(appDatabaseProvider)),
);

final healthSettingsOpenerProvider = Provider<HealthSettingsOpener>(
  (ref) => MethodChannelHealthSettingsOpener(
    fallback: () => ref.read(appPermissionsProvider).openSettings(),
  ),
);

final outboxSummaryProvider = FutureProvider<OutboxSummary>((ref) {
  ref.watch(healthSyncProvider.select((state) => state.lastRunAt));
  return ref.watch(outboxSummaryReaderProvider).summary();
});

final healthAccessProvider =
    FutureProvider<Map<HealthRecordKind, HealthAccess>>((ref) async {
      ref.watch(healthSyncProvider.select((state) => state.lastRunAt));
      final writer = ref.watch(healthWriterProvider);
      return {
        for (final kind in HealthRecordKind.values)
          if (writableHealthKinds.contains(kind))
            kind: await writer.access(kind),
      };
    });

final healthStatusProvider = FutureProvider<HealthStatusView>((ref) async {
  final access = await ref.watch(healthAccessProvider.future);
  final outbox = await ref.watch(outboxSummaryProvider.future);
  final disabled = await ref.watch(healthWritesProvider.future);
  return HealthStatusView(access: access, outbox: outbox, disabled: disabled);
});

final healthWriteToggleStoreProvider = Provider<HealthWriteToggleStore>(
  (ref) => HealthOutboxDao(ref.watch(appDatabaseProvider)),
);

final healthWritesProvider =
    AsyncNotifierProvider<HealthWritesController, Set<HealthRecordKind>>(
      HealthWritesController.new,
    );

class HealthWritesController extends AsyncNotifier<Set<HealthRecordKind>> {
  @override
  Future<Set<HealthRecordKind>> build() =>
      ref.watch(healthWritePreferencesProvider).disabled();

  Future<void> setEnabled(
    HealthRecordKind kind, {
    required bool enabled,
  }) async {
    final disabled = await future;
    state = AsyncData(
      enabled ? disabled.difference({kind}) : {...disabled, kind},
    );
    await ref
        .read(healthWritePreferencesProvider)
        .setEnabled(kind, enabled: enabled);
    final rows = ref.read(healthWriteToggleStoreProvider);
    if (enabled) {
      await rows.restoreDisabled(kind);
    } else {
      await rows.disablePending(kind, at: ref.read(clockProvider)());
    }
    ref.invalidate(outboxSummaryProvider);
    if (enabled) await ref.read(healthSyncProvider.notifier).process();
  }
}

final deadOutboxStoreProvider = Provider<DeadOutboxStore>(
  (ref) => HealthOutboxDao(ref.watch(appDatabaseProvider)),
);

final retryDeadHealthRowsProvider = Provider<RetryDeadHealthRows>(
  (ref) => RetryDeadHealthRows(
    outbox: ref.watch(deadOutboxStoreProvider),
    process: () => ref.read(healthSyncProvider.notifier).process(),
  ),
);

final healthGrantRetryProvider = Provider<void>((ref) {
  final watch = HealthGrantWatch();
  ref.listen(healthAccessProvider, (_, next) {
    if (next case AsyncData(:final value) when watch.observe(value)) {
      unawaited(
        ref
            .read(retryDeadHealthRowsProvider)
            .afterGrant()
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }, fireImmediately: true);
});
