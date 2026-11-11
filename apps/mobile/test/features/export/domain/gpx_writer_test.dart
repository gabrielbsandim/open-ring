import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/domain/gpx_writer.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:xml/xml.dart';

final _exportedAt = DateTime.utc(2026, 11, 10, 15);

WorkoutRoute _route() => WorkoutRoute(
  name: 'Morning run & <hills>',
  activityType: 'running',
  segments: [
    [
      TrackPoint(
        at: DateTime.utc(2026, 11, 10, 9, 0, 10),
        latitude: -23.5506,
        longitude: -46.6334,
        elevationMeters: 761.25,
      ),
      TrackPoint(
        at: DateTime.utc(2026, 11, 10, 9),
        latitude: -23.55052,
        longitude: -46.63331,
        elevationMeters: 760,
        heartRateBpm: 128,
      ),
    ],
    const [],
    [
      TrackPoint(
        at: DateTime.utc(2026, 11, 10, 9, 5),
        latitude: -23.551,
        longitude: -46.634,
        heartRateBpm: 0,
      ),
    ],
  ],
);

List<String> _children(XmlElement element) => [
  for (final child in element.childElements) child.name.local,
];

void main() {
  test('golden GPX 1.1 document', () {
    expect(
      gpxDocument(_route(), exportedAt: _exportedAt),
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<gpx version="1.1" creator="OpenRing"'
      ' xmlns="http://www.topografix.com/GPX/1/1"'
      ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
      ' xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"'
      ' xsi:schemaLocation="http://www.topografix.com/GPX/1/1'
      ' http://www.topografix.com/GPX/1/1/gpx.xsd'
      ' http://www.garmin.com/xmlschemas/TrackPointExtension/v1'
      ' http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd">\n'
      '  <metadata>\n'
      '    <name>Morning run &amp; &lt;hills&gt;</name>\n'
      '    <time>2026-11-10T15:00:00Z</time>\n'
      '  </metadata>\n'
      '  <trk>\n'
      '    <name>Morning run &amp; &lt;hills&gt;</name>\n'
      '    <type>running</type>\n'
      '    <trkseg>\n'
      '      <trkpt lat="-23.55052" lon="-46.63331">\n'
      '        <ele>760</ele>\n'
      '        <time>2026-11-10T09:00:00Z</time>\n'
      '        <extensions>\n'
      '          <gpxtpx:TrackPointExtension>\n'
      '            <gpxtpx:hr>128</gpxtpx:hr>\n'
      '          </gpxtpx:TrackPointExtension>\n'
      '        </extensions>\n'
      '      </trkpt>\n'
      '      <trkpt lat="-23.5506" lon="-46.6334">\n'
      '        <ele>761.25</ele>\n'
      '        <time>2026-11-10T09:00:10Z</time>\n'
      '      </trkpt>\n'
      '    </trkseg>\n'
      '    <trkseg>\n'
      '      <trkpt lat="-23.551" lon="-46.634">\n'
      '        <time>2026-11-10T09:05:00Z</time>\n'
      '      </trkpt>\n'
      '    </trkseg>\n'
      '  </trk>\n'
      '</gpx>\n',
    );
  });

  group('structure', () {
    late XmlElement gpx;

    setUp(() {
      gpx = XmlDocument.parse(gpxDocument(_route(), exportedAt: _exportedAt))
          .rootElement;
    });

    test('root is a GPX 1.1 element with both namespaces declared', () {
      expect(gpx.name.local, 'gpx');
      expect(gpx.name.namespaceUri, gpxNamespace);
      expect(gpx.getAttribute('version'), '1.1');
      expect(gpx.getAttribute('creator'), gpxCreator);
      expect(gpx.getAttribute('xmlns'), gpxNamespace);
      expect(gpx.getAttribute('xmlns:gpxtpx'), trackPointExtensionNamespace);
      final schemaLocation = gpx.getAttribute('xsi:schemaLocation')!.split(' ');
      expect(schemaLocation, [
        gpxNamespace,
        gpxSchema,
        trackPointExtensionNamespace,
        trackPointExtensionSchema,
      ]);
    });

    test('children follow the xsd sequence order', () {
      expect(_children(gpx), ['metadata', 'trk']);
      expect(_children(gpx.getElement('metadata')!), ['name', 'time']);
      final trk = gpx.getElement('trk')!;
      expect(_children(trk), ['name', 'type', 'trkseg', 'trkseg']);
      final points = trk.findAllElements('trkpt').toList();
      expect(
        [for (final p in points) _children(p)],
        [
          ['ele', 'time', 'extensions'],
          ['ele', 'time'],
          ['time'],
        ],
      );
    });

    test('every GPX element is in the GPX namespace', () {
      for (final element in gpx.descendantElements) {
        if (element.name.prefix == 'gpxtpx') continue;
        expect(element.name.namespaceUri, gpxNamespace, reason: '$element');
      }
    });

    test('heart rate sits in the Garmin TrackPointExtension namespace', () {
      final hr = gpx
          .findAllElements('hr', namespaceUri: trackPointExtensionNamespace)
          .toList();
      expect(hr, hasLength(1));
      expect(hr.single.innerText, '128');
      expect(hr.single.parentElement!.name.local, 'TrackPointExtension');
      expect(
        hr.single.parentElement!.name.namespaceUri,
        trackPointExtensionNamespace,
      );
      expect(hr.single.parentElement!.parentElement!.name.local, 'extensions');
    });

    test('points are written in time order with UTC times', () {
      final times = [
        for (final time in gpx.findAllElements('time').skip(1))
          DateTime.parse(time.innerText),
      ];
      expect(times, [
        DateTime.utc(2026, 11, 10, 9),
        DateTime.utc(2026, 11, 10, 9, 0, 10),
        DateTime.utc(2026, 11, 10, 9, 5),
      ]);
      expect(times.every((t) => t.isUtc), isTrue);
    });
  });

  test('an empty route is a valid GPX with an empty track', () {
    final gpx = XmlDocument.parse(
      gpxDocument(WorkoutRoute(segments: const []), exportedAt: _exportedAt),
    ).rootElement;

    expect(_children(gpx), ['metadata', 'trk']);
    expect(_children(gpx.getElement('trk')!), isEmpty);
  });

  test('coordinates outside the GPX ranges are rejected', () {
    final at = DateTime.utc(2026, 11, 10);
    expect(
      () => TrackPoint(at: at, latitude: 90.1, longitude: 0),
      throwsRangeError,
    );
    expect(
      () => TrackPoint(at: at, latitude: 0, longitude: 180),
      throwsRangeError,
    );
    expect(
      () => TrackPoint(at: at, latitude: double.nan, longitude: 0),
      throwsRangeError,
    );
  });
}
