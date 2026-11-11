import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/export/domain/csv_export_writer.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/domain/gpx_writer.dart';
import 'package:open_ring/features/export/domain/json_export_writer.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';
import 'package:open_ring/features/export/domain/workout_csv_writer.dart';
import 'package:open_ring/features/export/infrastructure/export_pages_dao.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:path_provider/path_provider.dart';

final class DriftDataExporter implements DataExporter {
  new({
    required AppDatabase database,
    required this._clock,
    this._directory = getTemporaryDirectory,
    int pageSize = ExportPagesDao.defaultPageSize,
  }) : _pages = ExportPagesDao(database, pageSize: pageSize);

  static const filePrefix = 'openring';

  final ExportPagesDao _pages;
  final DateTime Function() _clock;
  final Future<Directory> Function() _directory;

  @override
  Future<ExportResult> export(ExportRequest request) async {
    final now = _clock();
    final folder = await _workFolder();
    try {
      return switch (request.format) {
        ExportFormat.csv => await _csv(request, folder, now),
        ExportFormat.json => await _json(request, folder, now),
      };
    } on Object {
      await folder.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<ExportFile> exportRoute(WorkoutRoute route) async {
    final now = _clock();
    final folder = await _workFolder();
    final file = File('${folder.path}/$filePrefix-route-${_stamp(now)}.gpx');
    await _write(file, (sink) async => writeGpx(route, sink, exportedAt: now));
    return ExportFile(path: file.path, mimeType: ExportFile.gpxMimeType);
  }

  @override
  Future<ExportFile> exportWorkoutCsv(
    FinishedWorkout workout, {
    required Duration offset,
  }) async {
    final folder = await _workFolder();
    final name = '$filePrefix-workout-${_stamp(_clock())}.csv';
    final file = File('${folder.path}/$name');
    await _write(
      file,
      (sink) async => writeWorkoutCsv(workout, sink, offset: offset),
    );
    return ExportFile(path: file.path, mimeType: ExportFile.csvMimeType);
  }

  Future<ExportResult> _csv(
    ExportRequest request,
    Directory folder,
    DateTime now,
  ) async {
    final single = request.kinds.length == 1;
    final counts = <ExportKind, int>{};
    final files = <File>[];
    for (final kind in request.kinds) {
      final name = single
          ? '$filePrefix-${kind.key}-${_stamp(now)}.csv'
          : '${kind.key}.csv';
      final file = File('${folder.path}/$name');
      await _write(file, (sink) async {
        final writer = CsvExportWriter(kind, sink)..writeHeader();
        counts[kind] = await _drain(kind, request, writer.write, sink);
      });
      files.add(file);
    }
    if (single) {
      return ExportResult(
        files: [
          ExportFile(path: files.single.path, mimeType: ExportFile.csvMimeType),
        ],
        counts: counts,
      );
    }
    final zip = await _zip(
      files,
      '${folder.path}/$filePrefix-csv-${_stamp(now)}.zip',
    );
    return ExportResult(
      files: [ExportFile(path: zip.path, mimeType: ExportFile.zipMimeType)],
      counts: counts,
    );
  }

  Future<ExportResult> _json(
    ExportRequest request,
    Directory folder,
    DateTime now,
  ) async {
    final counts = <ExportKind, int>{};
    final file = File('${folder.path}/$filePrefix-${_stamp(now)}.json');
    final header = ExportHeader(
      exportedAt: OffsetTime.of(now),
      from: OffsetTime.of(request.from),
      to: OffsetTime.of(request.to),
      device: await _pages.latestDevice(),
    );
    await _write(file, (sink) async {
      final writer = JsonExportWriter(sink)..begin(header);
      for (final kind in request.kinds) {
        writer.beginKind(kind);
        counts[kind] = await _drain(kind, request, writer.write, sink);
        writer.endKind();
      }
      writer.end();
    });
    return ExportResult(
      files: [ExportFile(path: file.path, mimeType: ExportFile.jsonMimeType)],
      counts: counts,
    );
  }

  Future<int> _drain(
    ExportKind kind,
    ExportRequest request,
    void Function(ExportRecord record) write,
    IOSink sink,
  ) async {
    var count = 0;
    await for (final page in _pages.pages(
      kind,
      from: request.from,
      to: request.to,
    )) {
      page.forEach(write);
      count += page.length;
      await sink.flush();
    }
    return count;
  }

  Future<File> _zip(List<File> files, String path) async {
    final encoder = ZipFileEncoder()..create(path);
    for (final file in files) {
      await encoder.addFile(file);
    }
    await encoder.close();
    for (final file in files) {
      await file.delete();
    }
    return File(path);
  }

  Future<Directory> _workFolder() =>
      _directory().then((root) => root.createTemp('$filePrefix-export-'));

  static Future<void> _write(
    File file,
    Future<void> Function(IOSink sink) body,
  ) async {
    final sink = file.openWrite();
    try {
      await body(sink);
    } finally {
      await sink.close();
    }
  }

  static String _stamp(DateTime at) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${at.year}${pad(at.month)}${pad(at.day)}'
        '-${pad(at.hour)}${pad(at.minute)}${pad(at.second)}';
  }
}
