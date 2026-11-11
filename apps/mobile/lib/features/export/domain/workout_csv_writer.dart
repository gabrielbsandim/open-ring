import 'dart:collection';

import 'package:open_ring/features/export/domain/csv_export_writer.dart';
import 'package:open_ring/features/export/domain/export_values.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

const workoutCsvColumns = [
  'time',
  'bpm',
  'latitude',
  'longitude',
  'elevation_m',
  'accuracy_m',
];

final class _Row {
  int? bpm;
  TrackPoint? point;
}

void writeWorkoutCsv(
  FinishedWorkout workout,
  StringSink sink, {
  required Duration offset,
}) {
  sink.write(csvLine(workoutCsvColumns));
  final rows = SplayTreeMap<int, _Row>();
  for (final sample in workout.heartRate) {
    rows.putIfAbsent(sample.at.millisecondsSinceEpoch, _Row.new).bpm =
        sample.bpm;
  }
  for (final point in workout.route.points) {
    rows.putIfAbsent(point.at.millisecondsSinceEpoch, _Row.new).point = point;
  }
  rows.forEach(
    (utcMs, row) => sink.write(csvLine(_fields(utcMs, row, offset))),
  );
}

List<String> _fields(int utcMs, _Row row, Duration offset) {
  final point = row.point;
  final time = OffsetTime(utcMs: utcMs, offsetMinutes: offset.inMinutes);
  return [
    time.toIso8601(),
    exportText(row.bpm ?? point?.heartRateBpm),
    _coordinate(point?.latitude),
    _coordinate(point?.longitude),
    exportText(point?.elevationMeters),
    exportText(point?.accuracyMeters),
  ];
}

String _coordinate(double? value) =>
    value == null ? '' : formatDecimal(value, digits: coordinateDecimals);
