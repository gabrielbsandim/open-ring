import 'package:flutter/services.dart';
import 'package:health_connect_writer/health_connect_writer.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_reader.dart';

final class MethodChannelExerciseSessions implements ExerciseSessionSource {
  const new({this.channel = const MethodChannel(channelName)});

  static const String channelName = HealthConnectChannels.exercise;

  final MethodChannel channel;

  @override
  Future<ExternalRead<ExternalWorkout>> read({
    required DateTime from,
    required DateTime to,
  }) async {
    final sessions =
        await channel.invokeListMethod<Object?>('read', {
          'from': from.utcMs,
          'to': to.utcMs,
        }) ??
        const [];
    final maps = sessions.whereType<Map<Object?, Object?>>().toList();
    return ExternalRead(
      [for (final session in maps) ?workoutOf(session)],
      present: {
        for (final session in maps)
          if (session['id'] case final String id) id,
      },
    );
  }

  static ExternalWorkout? workoutOf(Map<Object?, Object?> session) {
    if (session case {
      'id': final String id,
      'source': final String source,
      'activityType': final String activityType,
      'start': final int startMs,
      'end': final int endMs,
    }) {
      final start = utcInstant(startMs);
      final offsetSeconds = session['offsetSeconds'];
      return ExternalWorkout(
        recordId: id,
        source: source,
        activityType: activityType,
        start: start,
        end: utcInstant(endMs),
        utcOffset: offsetSeconds is int
            ? Duration(seconds: offsetSeconds)
            : start.toLocal().timeZoneOffset,
      );
    }
    return null;
  }
}
