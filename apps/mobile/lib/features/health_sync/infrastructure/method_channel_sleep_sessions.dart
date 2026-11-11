import 'package:flutter/services.dart';
import 'package:health_connect_writer/health_connect_writer.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_reader.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';

final class MethodChannelSleepSessions
    implements SleepSessionWriter, SleepSessionIdSource {
  const new({this.channel = const MethodChannel(channelName)});

  static const String channelName = HealthConnectChannels.sleep;

  final MethodChannel channel;

  // A failed id read only skips removing deleted nights this time.
  @override
  Future<Set<String>?> ids({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final ids = await channel.invokeListMethod<Object?>('ids', {
        'from': from.utcMs,
        'to': to.utcMs,
      });
      return ids?.whereType<String>().toSet();
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> deleteRange({required DateTime from, required DateTime to}) =>
      channel.invokeMethod<void>('deleteRange', {
        'from': from.utcMs,
        'to': to.utcMs,
      });

  @override
  Future<void> write(SleepEntry night, {required int version}) => channel
      .invokeMethod<void>('write', sessionArguments(night, version: version));

  static Map<String, Object> sessionArguments(
    SleepEntry night, {
    required int version,
  }) => {
    'clientRecordId': night.id,
    'version': version,
    'start': night.start.utcMs,
    'end': night.end.utcMs,
    'stages': stageArguments(night),
  };

  // Health Connect rejects a session whose stages overlap or leave its span.
  static List<Map<String, Object>> stageArguments(SleepEntry night) {
    final ordered = [...night.stages]
      ..sort((a, b) => a.start.compareTo(b.start));
    final stages = <Map<String, Object>>[];
    var floor = night.start;
    for (final stage in ordered) {
      final start = stage.start.isBefore(floor) ? floor : stage.start;
      final end = stage.end.isAfter(night.end) ? night.end : stage.end;
      if (!end.isAfter(start)) continue;
      stages.add({
        'start': start.utcMs,
        'end': end.utcMs,
        'stage': stage.stage.name,
      });
      floor = end;
    }
    return stages;
  }
}
