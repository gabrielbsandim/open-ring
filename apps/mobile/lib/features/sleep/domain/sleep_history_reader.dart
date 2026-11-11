import 'package:metrics/metrics.dart';

abstract interface class SleepHistoryReader {
  Future<List<SleepSpan>> sleepSpans({
    required DateTime from,
    required DateTime to,
  });
}

final class EmptySleepHistoryReader implements SleepHistoryReader {
  const new();

  @override
  Future<List<SleepSpan>> sleepSpans({
    required DateTime from,
    required DateTime to,
  }) async => const [];
}
