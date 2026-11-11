import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/heart/domain/heart_history_reader.dart';
import 'package:open_ring/features/heart/infrastructure/heart_samples_dao.dart';

final class DriftHeartHistoryReader implements HeartHistoryReader {
  new(AppDatabase db) : _dao = HeartSamplesDao(db);

  final HeartSamplesDao _dao;

  @override
  Future<List<BpmSample>> heartRate({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final row in await _dao.heartRate(from, to))
      (at: utcInstant(row.atUtcMs), bpm: row.bpm),
  ];

  @override
  Future<List<HrvReading>> hrv({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final row in await _dao.hrv(from, to))
      (at: utcInstant(row.atUtcMs), milliseconds: row.milliseconds),
  ];

  @override
  Future<List<Spo2Reading>> spo2({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final row in await _dao.spo2(from, to))
      (at: utcInstant(row.atUtcMs), percent: row.percent),
  ];

  @override
  Future<List<StressReading>> stress({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final row in await _dao.stress(from, to))
      (at: utcInstant(row.atUtcMs), level: row.level),
  ];
}
