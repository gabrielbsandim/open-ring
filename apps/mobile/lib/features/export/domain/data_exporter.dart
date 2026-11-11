import 'package:meta/meta.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

abstract interface class DataExporter {
  Future<ExportResult> export(ExportRequest request);

  Future<ExportFile> exportRoute(WorkoutRoute route);

  Future<ExportFile> exportWorkoutCsv(
    FinishedWorkout workout, {
    required Duration offset,
  });
}

@immutable
final class ExportFile {
  const new({required this.path, required this.mimeType});

  static const csvMimeType = 'text/csv';
  static const jsonMimeType = 'application/json';
  static const zipMimeType = 'application/zip';
  static const gpxMimeType = 'application/gpx+xml';

  final String path;
  final String mimeType;
}

@immutable
final class ExportResult {
  new({required List<ExportFile> files, required Map<ExportKind, int> counts})
    : files = List.unmodifiable(files),
      counts = Map.unmodifiable(counts);

  final List<ExportFile> files;
  final Map<ExportKind, int> counts;

  int get recordCount => counts.values.fold(0, (sum, count) => sum + count);
}
