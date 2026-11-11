import 'package:metrics/metrics.dart';

abstract interface class HeartHistoryReader {
  Future<List<BpmSample>> heartRate({
    required DateTime from,
    required DateTime to,
  });

  Future<List<HrvReading>> hrv({required DateTime from, required DateTime to});

  Future<List<Spo2Reading>> spo2({
    required DateTime from,
    required DateTime to,
  });

  Future<List<StressReading>> stress({
    required DateTime from,
    required DateTime to,
  });
}

final class EmptyHeartHistoryReader implements HeartHistoryReader {
  const new();

  @override
  Future<List<BpmSample>> heartRate({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<List<HrvReading>> hrv({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<List<Spo2Reading>> spo2({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<List<StressReading>> stress({
    required DateTime from,
    required DateTime to,
  }) async => const [];
}
