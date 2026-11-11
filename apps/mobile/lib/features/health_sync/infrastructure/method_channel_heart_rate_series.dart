import 'package:flutter/services.dart';
import 'package:health_connect_writer/health_connect_writer.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/heart_rate_series.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';

final class MethodChannelHeartRateSeries implements HeartRateSeriesWriter {
  const new({this.channel = const MethodChannel(channelName)});

  static const String channelName = HealthConnectChannels.heartRate;

  static const maxRecordsPerInsert = 1000;

  static const int maxSamplesPerInsert = maxSeriesSamples;

  final MethodChannel channel;

  @override
  Future<void> deleteRange({required DateTime from, required DateTime to}) =>
      channel.invokeMethod<void>('deleteRange', {
        'from': from.utcMs,
        'to': to.utcMs,
      });

  @override
  Future<void> write(
    List<HeartRateSeriesEntry> series, {
    required int version,
    required bool active,
  }) async {
    for (final chunk in insertChunks(series)) {
      await channel.invokeMethod<void>('write', {
        'version': version,
        'active': active,
        'records': [for (final record in chunk) recordArguments(record)],
      });
    }
  }

  static Iterable<List<HeartRateSeriesEntry>> insertChunks(
    List<HeartRateSeriesEntry> series, {
    int maxRecords = maxRecordsPerInsert,
    int maxSamples = maxSamplesPerInsert,
  }) sync* {
    var chunk = <HeartRateSeriesEntry>[];
    var samples = 0;
    for (final record in series.where((s) => s.samples.isNotEmpty)) {
      final full =
          chunk.length >= maxRecords ||
          samples + record.samples.length > maxSamples;
      if (full && chunk.isNotEmpty) {
        yield chunk;
        chunk = [];
        samples = 0;
      }
      chunk.add(record);
      samples += record.samples.length;
    }
    if (chunk.isNotEmpty) yield chunk;
  }

  static Map<String, Object> recordArguments(HeartRateSeriesEntry series) => {
    'clientRecordId': series.id,
    'start': series.start.utcMs,
    'end': series.end.utcMs,
    'times': [for (final sample in series.samples) sample.at.utcMs],
    'bpm': [for (final sample in series.samples) sample.bpm],
  };
}
