import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

// Without a ring the job only reads Health Connect, which a background run
// can do only with the background grant.
Future<bool> wantsBackgroundSync({
  required SyncStore rings,
  required HealthReadStore reads,
  required HealthReader reader,
}) async {
  if (await rings.pairedRing() != null) return true;
  try {
    return await _readsInBackground(reads, reader).timeout(ringlessImportLimit);
  } on Object catch (error) {
    debugPrint('Background read state unavailable, job left off: $error');
    return false;
  }
}

Future<bool> _readsInBackground(
  HealthReadStore reads,
  HealthReader reader,
) async {
  if (!await _anyReadOn(reads)) return false;
  return await reader.backgroundReadAllowed();
}

Future<bool> _anyReadOn(HealthReadStore reads) async {
  final (sleep, workout) = await (
    reads.settings(HealthRecordKind.sleep),
    reads.settings(HealthRecordKind.workout),
  ).wait;
  return sleep.enabled || workout.enabled;
}

final class EnableBackgroundReads {
  const new({
    required this.demo,
    required this.rings,
    required this.reads,
    required this.reader,
    required this.reschedule,
  });

  final bool Function() demo;
  final SyncStore rings;
  final HealthReadStore reads;
  final HealthReader reader;
  final Future<void> Function() reschedule;

  // Asked only when the job would read without a ring; a refusal leaves
  // the foreground imports working.
  Future<bool> call() async {
    if (demo()) return false;
    if (await rings.pairedRing() != null) return false;
    if (!await _anyReadOn(reads)) return false;
    final allowed = await _allow();
    await reschedule();
    return allowed;
  }

  Future<bool> _allow() async {
    if (await reader.backgroundReadAllowed()) return true;
    return await reader.requestBackgroundReadAccess();
  }
}

final enableBackgroundReadsProvider = Provider<EnableBackgroundReads>(
  (ref) => EnableBackgroundReads(
    demo: () => ref.read(demoModeProvider),
    rings: ref.watch(syncStoreProvider),
    reads: ref.watch(healthReadStoreProvider),
    reader: ref.watch(healthReaderProvider),
    reschedule: () => ref.read(syncIntervalProvider.notifier).ensureScheduled(),
  ),
);
