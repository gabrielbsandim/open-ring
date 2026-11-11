import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/source_priority.dart';

typedef ImportedSleep = ({
  List<String> priority,
  Map<String, List<SleepSpan>> spans,
});

const ImportedSleep noImportedSleep = (priority: [ringSource], spans: {});

abstract interface class ImportedSleepReader {
  // Spans other apps wrote, keyed by source, and the order that picks among
  // them; when reading is off the order holds the ring only.
  Future<ImportedSleep> importedSleep({
    required DateTime from,
    required DateTime to,
  });
}

final class NoImportedSleepReader implements ImportedSleepReader {
  const new();

  @override
  Future<ImportedSleep> importedSleep({
    required DateTime from,
    required DateTime to,
  }) async => noImportedSleep;
}
