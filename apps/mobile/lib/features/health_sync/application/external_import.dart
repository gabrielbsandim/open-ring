import 'package:meta/meta.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

enum ImportOutcome { off, unavailable, denied, deferred, imported }

@immutable
final class ImportReport {
  const new(this.outcome, {this.count = 0});

  final ImportOutcome outcome;
  final int count;
}

abstract interface class ExternalImport {
  Future<ImportReport> call();
}

const firstImportWindow = Duration(days: 30);
const importOverlap = Duration(days: 2);

// A record the other app revised after the last read still starts inside
// the overlap, so it is read again and replaced.
DateTime importWindowStart(DateTime? lastReadAt, DateTime now) {
  final first = now.subtract(firstImportWindow);
  if (lastReadAt == null) return first;
  final since = lastReadAt.subtract(importOverlap);
  return since.isBefore(first) ? first : since;
}

ReadCoverage? coverageOf(
  ExternalRead<Object?> read, {
  required DateTime from,
  required DateTime to,
}) {
  final present = read.present;
  if (present == null) return null;
  return (from: from, to: to, present: present);
}

ImportOutcome blockedOutcome(HealthAccess access) => switch (access) {
  HealthAccess.denied => ImportOutcome.denied,
  HealthAccess.unavailable => ImportOutcome.unavailable,
  HealthAccess.deferred => ImportOutcome.deferred,
  HealthAccess.granted => ImportOutcome.imported,
};
