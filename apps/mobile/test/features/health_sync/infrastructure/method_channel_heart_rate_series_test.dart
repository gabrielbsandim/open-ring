import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_heart_rate_series.dart';

DateTime at(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 10, hour, minute);

HeartRateSeriesEntry series(int hour, {int samples = 2}) =>
    HeartRateSeriesEntry(
      id: HealthRecordId.of(
        'ring-1',
        HealthEntryType.heartRateSeries,
        at(hour),
      ),
      start: at(hour),
      end: at(hour, (samples - 1) * 5),
      samples: [
        for (var i = 0; i < samples; i++)
          HeartRateEntry(id: 'hr-$hour-$i', at: at(hour, i * 5), bpm: 60 + i),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MethodChannelHeartRateSeries.channelName);
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply(call);
        });
    addTearDown(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  test('a series goes out as one record holding every sample', () async {
    answer((_) => null);

    await const MethodChannelHeartRateSeries().write(
      [series(14)],
      version: 7,
      active: true,
    );

    final call = calls.single;
    expect(call.method, 'write');
    expect(call.arguments, {
      'version': 7,
      'active': true,
      'records': [
        {
          'clientRecordId':
              'openring:ring-1:heartRateSeries:${at(14).millisecondsSinceEpoch}',
          'start': at(14).millisecondsSinceEpoch,
          'end': at(14, 5).millisecondsSinceEpoch,
          'times': [
            at(14).millisecondsSinceEpoch,
            at(14, 5).millisecondsSinceEpoch,
          ],
          'bpm': [60, 61],
        },
      ],
    });
  });

  test('inserts respect both the record and the sample limits', () {
    final records = [for (var h = 0; h < 5; h++) series(h, samples: 3)];

    final byRecords = MethodChannelHeartRateSeries.insertChunks(
      records,
      maxRecords: 2,
    );
    final bySamples = MethodChannelHeartRateSeries.insertChunks(
      records,
      maxSamples: 7,
    );

    expect(byRecords.map((c) => c.length), [2, 2, 1]);
    expect(bySamples.map((c) => c.length), [2, 2, 1]);
  });

  test('the default limits are Health Connect insert limits', () {
    final records = [for (var i = 0; i < 2500; i++) series(0, samples: 1)];

    final chunks = MethodChannelHeartRateSeries.insertChunks(records);

    expect(chunks.map((c) => c.length), [1000, 1000, 500]);
    expect(MethodChannelHeartRateSeries.maxRecordsPerInsert, 1000);
  });

  test('nothing is sent for series without samples', () async {
    answer((_) => null);

    await const MethodChannelHeartRateSeries().write(
      [series(1, samples: 0)],
      version: 1,
      active: false,
    );

    expect(calls, isEmpty);
  });

  test('the range delete sends both ends in UTC milliseconds', () async {
    answer((_) => null);

    await const MethodChannelHeartRateSeries().deleteRange(
      from: at(0),
      to: at(8),
    );

    expect(calls.single.method, 'deleteRange');
    expect(calls.single.arguments, {
      'from': at(0).millisecondsSinceEpoch,
      'to': at(8).millisecondsSinceEpoch,
    });
  });

  test('a platform error reaches the outbox as a failure', () async {
    answer((_) => throw PlatformException(code: 'health_connect_heart_rate'));

    await expectLater(
      const MethodChannelHeartRateSeries().write(
        [series(2)],
        version: 1,
        active: false,
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}
