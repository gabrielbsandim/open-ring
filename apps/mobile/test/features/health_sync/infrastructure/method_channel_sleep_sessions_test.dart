import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_sleep_sessions.dart';
import 'package:ring_driver/ring_driver.dart';

DateTime at(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 10, hour, minute);

SleepStageEntry stage(int from, int to, SleepStage kind) => SleepStageEntry(
  id: 'stage-$from',
  start: at(0, from),
  end: at(0, to),
  stage: kind,
);

final String sessionId = HealthRecordId.of(
  'ring-1',
  HealthEntryType.sleepSession,
  at(0),
);

SleepEntry nightWith(List<SleepStageEntry> stages) =>
    SleepEntry(id: sessionId, start: at(0), end: at(1), stages: stages);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MethodChannelSleepSessions.channelName);
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

  test('a night goes out as one session holding every stage', () async {
    answer((_) => null);
    final night = nightWith([
      stage(0, 17, SleepStage.light),
      stage(17, 40, SleepStage.deep),
      stage(40, 52, SleepStage.rem),
      stage(52, 60, SleepStage.awake),
    ]);

    await const MethodChannelSleepSessions().write(night, version: 7);

    final call = calls.single;
    expect(call.method, 'write');
    expect(call.arguments, {
      'clientRecordId':
          'openring:ring-1:sleepSession:${at(0).millisecondsSinceEpoch}',
      'version': 7,
      'start': at(0).millisecondsSinceEpoch,
      'end': at(1).millisecondsSinceEpoch,
      'stages': [
        for (final (from, to, name) in [
          (0, 17, 'light'),
          (17, 40, 'deep'),
          (40, 52, 'rem'),
          (52, 60, 'awake'),
        ])
          {
            'start': at(0, from).millisecondsSinceEpoch,
            'end': at(0, to).millisecondsSinceEpoch,
            'stage': name,
          },
      ],
    });
  });

  test('a revised night upserts under the same id with its version', () {
    final first = MethodChannelSleepSessions.sessionArguments(
      nightWith([stage(0, 60, SleepStage.light)]),
      version: 1,
    );
    final revised = MethodChannelSleepSessions.sessionArguments(
      nightWith([
        stage(0, 30, SleepStage.light),
        stage(30, 60, SleepStage.rem),
      ]),
      version: 2,
    );

    expect(revised['clientRecordId'], first['clientRecordId']);
    expect((first['version'], revised['version']), (1, 2));
  });

  test('stages are sorted, clipped to the night and never overlap', () {
    final stages = MethodChannelSleepSessions.stageArguments(
      SleepEntry(
        id: sessionId,
        start: at(0, 10),
        end: at(0, 50),
        stages: [
          stage(30, 55, SleepStage.rem),
          stage(5, 20, SleepStage.light),
          stage(15, 30, SleepStage.deep),
          stage(20, 25, SleepStage.awake),
        ],
      ),
    );

    expect(
      [
        for (final s in stages)
          (
            DateTime.fromMillisecondsSinceEpoch(
              s['start']! as int,
              isUtc: true,
            ).minute,
            DateTime.fromMillisecondsSinceEpoch(
              s['end']! as int,
              isUtc: true,
            ).minute,
            s['stage'],
          ),
      ],
      [(10, 20, 'light'), (20, 30, 'deep'), (30, 50, 'rem')],
    );
  });

  test('the range delete sends both ends in UTC milliseconds', () async {
    answer((_) => null);

    await const MethodChannelSleepSessions().deleteRange(
      from: at(0),
      to: at(8),
    );

    expect(calls.single.method, 'deleteRange');
    expect(calls.single.arguments, {
      'from': at(0).millisecondsSinceEpoch,
      'to': at(8).millisecondsSinceEpoch,
    });
  });

  test('session ids come back as a set for the read window', () async {
    answer((_) => ['s1', 's2']);

    final ids = await const MethodChannelSleepSessions().ids(
      from: at(0),
      to: at(8),
    );

    expect(ids, {'s1', 's2'});
    expect(calls.single.method, 'ids');
    expect(calls.single.arguments, {
      'from': at(0).millisecondsSinceEpoch,
      'to': at(8).millisecondsSinceEpoch,
    });
  });

  test('on a platform error the ids are unknown', () async {
    answer((_) => throw PlatformException(code: 'health_connect_sleep'));

    expect(
      await const MethodChannelSleepSessions().ids(from: at(0), to: at(8)),
      isNull,
    );
  });
}
