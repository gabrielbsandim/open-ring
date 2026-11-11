import 'package:open_ring/features/export/domain/export_values.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';

const gpxNamespace = 'http://www.topografix.com/GPX/1/1';
const gpxSchema = 'http://www.topografix.com/GPX/1/1/gpx.xsd';
const trackPointExtensionNamespace =
    'http://www.garmin.com/xmlschemas/TrackPointExtension/v1';
const trackPointExtensionSchema =
    'http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd';
const xsiNamespace = 'http://www.w3.org/2001/XMLSchema-instance';
const gpxCreator = 'OpenRing';

const _maxHeartRate = 255;

String gpxDocument(WorkoutRoute route, {required DateTime exportedAt}) {
  final buffer = StringBuffer();
  writeGpx(route, buffer, exportedAt: exportedAt);
  return buffer.toString();
}

// Element order follows the GPX 1.1 xsd sequences: metadata before trk;
// name, type, trkseg inside trk; ele, time, extensions inside trkpt.
void writeGpx(
  WorkoutRoute route,
  StringSink sink, {
  required DateTime exportedAt,
}) {
  sink
    ..write('<?xml version="1.0" encoding="UTF-8"?>\n')
    ..write('<gpx version="1.1" creator="$gpxCreator"')
    ..write(' xmlns="$gpxNamespace"')
    ..write(' xmlns:xsi="$xsiNamespace"')
    ..write(' xmlns:gpxtpx="$trackPointExtensionNamespace"')
    ..write(' xsi:schemaLocation="$gpxNamespace $gpxSchema')
    ..write(' $trackPointExtensionNamespace $trackPointExtensionSchema">\n')
    ..write('  <metadata>\n');
  _writeText(sink, '    ', 'name', route.name);
  _writeText(sink, '    ', 'time', _utc(exportedAt));
  sink
    ..write('  </metadata>\n')
    ..write('  <trk>\n');
  _writeText(sink, '    ', 'name', route.name);
  _writeText(sink, '    ', 'type', route.activityType);
  for (final segment in route.segments) {
    sink.write('    <trkseg>\n');
    for (final point in segment) {
      _writePoint(sink, point);
    }
    sink.write('    </trkseg>\n');
  }
  sink
    ..write('  </trk>\n')
    ..write('</gpx>\n');
}

void _writePoint(StringSink sink, TrackPoint point) {
  final lat = formatDecimal(point.latitude, digits: coordinateDecimals);
  final lon = formatDecimal(point.longitude, digits: coordinateDecimals);
  sink.write('      <trkpt lat="$lat" lon="$lon">\n');
  _writeText(sink, '        ', 'ele', _elevation(point.elevationMeters));
  _writeText(sink, '        ', 'time', _utc(point.at));
  _writeHeartRate(sink, point.heartRateBpm);
  sink.write('      </trkpt>\n');
}

void _writeHeartRate(StringSink sink, int? bpm) {
  if (bpm == null || bpm < 1 || bpm > _maxHeartRate) return;
  sink
    ..write('        <extensions>\n')
    ..write('          <gpxtpx:TrackPointExtension>\n')
    ..write('            <gpxtpx:hr>$bpm</gpxtpx:hr>\n')
    ..write('          </gpxtpx:TrackPointExtension>\n')
    ..write('        </extensions>\n');
}

void _writeText(StringSink sink, String indent, String tag, String? text) {
  if (text == null || text.isEmpty) return;
  sink.write('$indent<$tag>${_escape(text)}</$tag>\n');
}

String? _elevation(double? meters) {
  if (meters == null || !meters.isFinite) return null;
  return formatDecimal(meters);
}

String _utc(DateTime at) => OffsetTime.of(at).toUtcIso8601();

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
