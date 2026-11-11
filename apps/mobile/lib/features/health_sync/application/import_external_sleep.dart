import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/application/external_import.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

export 'package:open_ring/features/health_sync/application/external_import.dart';

final class ImportExternalSleep implements ExternalImport {
  const new({required this.reader, required this.store, required this.clock});

  final HealthReader reader;
  final HealthReadStore store;
  final DateTime Function() clock;

  @override
  Future<ImportReport> call() async {
    const kind = HealthRecordKind.sleep;
    final settings = await store.settings(kind);
    if (!settings.enabled) return const ImportReport(ImportOutcome.off);
    final access = await reader.readAccess(kind);
    if (access != HealthAccess.granted) {
      return ImportReport(blockedOutcome(access));
    }
    final now = clock();
    final from = importWindowStart(settings.lastReadAt, now);
    final read = await reader.sleepNights(from: from, to: now);
    final nights = [
      for (final night in read.records)
        if (isExternalSource(night.source) && night.hasSleep) night,
    ];
    await store.saveSleep(
      nights,
      readAt: now,
      coverage: coverageOf(read, from: from, to: now),
    );
    return ImportReport(ImportOutcome.imported, count: nights.length);
  }
}
