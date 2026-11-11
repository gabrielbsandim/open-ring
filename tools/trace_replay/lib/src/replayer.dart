import 'dart:async';

import 'package:meta/meta.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';
import 'package:ring_protocol/ring_protocol.dart';
import 'package:trace_replay/src/checksum_check.dart';
import 'package:trace_replay/src/describe.dart';
import 'package:trace_replay/src/hex.dart';
import 'package:trace_replay/src/trace.dart';

enum ReplayCall {
  syncTime,
  readBattery,
  findDevice,
  pullActivity,
  pullHeartRate,
  pullStress,
  pullHrv,
  pullSpo2,
  pullSleep;

  bool get perDay =>
      this == pullActivity || this == pullHeartRate || this == pullHrv;

  static ReplayCall? of(TraceEntry tx) {
    final bytes = tx.bytes;
    if (bytes.isEmpty) return null;
    return switch (tx.channel) {
      TraceChannel.v1Write => _v1(bytes.first),
      TraceChannel.bigDataWrite when bytes.length > 1 => _bigData(bytes[1]),
      _ => null,
    };
  }

  static ReplayCall? _v1(int command) => switch (V1Command.fromId(command)) {
    V1Command.setDateTime => syncTime,
    V1Command.battery => readBattery,
    V1Command.findDevice => findDevice,
    V1Command.activityLog => pullActivity,
    V1Command.heartRateLog => pullHeartRate,
    V1Command.stressLog => pullStress,
    V1Command.hrvLog => pullHrv,
    _ => null,
  };

  static ReplayCall? _bigData(int dataId) => switch (dataId) {
    BigDataId.spo2 => pullSpo2,
    BigDataId.sleep => pullSleep,
    _ => null,
  };
}

@immutable
final class ReplayStep {
  new({
    required this.call,
    required List<TraceEntry> requests,
    List<Object> records = const [],
    this.error,
  }) : requests = List.unmodifiable(requests),
       records = List.unmodifiable(records);

  final ReplayCall call;
  final List<TraceEntry> requests;
  final List<Object> records;
  final String? error;

  bool get failed => error != null;
}

@immutable
final class ReplayResult {
  new({
    required this.rule,
    required this.ruleDetected,
    required List<ReplayStep> steps,
    required List<TraceEntry> skipped,
  }) : steps = List.unmodifiable(steps),
       skipped = List.unmodifiable(skipped);

  final ChecksumRule rule;
  final bool ruleDetected;
  final List<ReplayStep> steps;
  final List<TraceEntry> skipped;
}

typedef _Plan = ({
  List<({ReplayCall call, List<TraceEntry> requests})> steps,
  List<TraceEntry> skipped,
});

final class TraceReplayer {
  const new({
    this.rule,
    this.now,
    this.timeout = const Duration(seconds: 1),
    this.deviceId = 'trace-replay',
  });

  final ChecksumRule? rule;
  final DateTime? now;
  final Duration timeout;
  final String deviceId;

  static final _since = DateTime.fromMillisecondsSinceEpoch(0);

  Future<ReplayResult> replay(List<TraceEntry> entries) async {
    final rule =
        this.rule ??
        ChecksumTally.ofEntries(
          entries,
          direction: TraceDirection.rx,
        ).likelyRule;
    final script = ReplayScript(entries);
    final transport = FakeBleTransport(responder: script.respond);
    final plan = _plan(entries);
    final steps = <ReplayStep>[];
    try {
      for (final step in plan.steps) {
        steps.add(await _run(transport, step.call, step.requests, rule));
      }
    } finally {
      await transport.close();
    }
    return ReplayResult(
      rule: rule,
      ruleDetected: this.rule == null,
      steps: steps,
      skipped: plan.skipped,
    );
  }

  static _Plan _plan(List<TraceEntry> entries) {
    final steps = <({ReplayCall call, List<TraceEntry> requests})>[];
    final skipped = <TraceEntry>[];
    ReplayCall? previous;
    for (final tx in entries.where((e) => e.isTx)) {
      final call = ReplayCall.of(tx);
      if (call == null) {
        skipped.add(tx);
        previous = null;
        continue;
      }
      final repeat = call == previous;
      previous = call;
      final last = steps.lastOrNull;
      if (repeat && last != null && _nextDay(last.requests, call, tx)) {
        last.requests.add(tx);
        continue;
      }
      steps.add((call: call, requests: [tx]));
    }
    return (steps: steps, skipped: skipped);
  }

  static bool _nextDay(
    List<TraceEntry> requests,
    ReplayCall call,
    TraceEntry tx,
  ) =>
      call.perDay &&
      !requests.any((r) => _samePrefix(r.bytes, tx.bytes, V1Frame.length - 1));

  Future<ReplayStep> _run(
    FakeBleTransport transport,
    ReplayCall call,
    List<TraceEntry> requests,
    ChecksumRule rule,
  ) async {
    final at = now ?? requests.first.at.toLocal();
    final driver = ColmiDriver(
      transport: transport,
      codec: rule.codec,
      clock: () => at,
      responseTimeout: timeout,
      historyDays: requests.length,
    );
    ReplayStep failed(String error) =>
        ReplayStep(call: call, requests: requests, error: error);
    try {
      await driver.connect(deviceId);
      final records = await _call(driver, call, at);
      return ReplayStep(call: call, requests: requests, records: records);
    } on ColmiProtocolException catch (e) {
      return failed(describeError(e.error));
    } on BleTransportException catch (e) {
      return failed(e.message);
    } on TimeoutException {
      return failed('no complete reply within ${timeout.inMilliseconds} ms');
    } finally {
      await driver.close();
    }
  }

  static Future<List<Object>> _call(
    ColmiDriver driver,
    ReplayCall call,
    DateTime at,
  ) async => switch (call) {
    ReplayCall.syncTime => await _syncTime(driver, at),
    ReplayCall.readBattery => [await driver.readBattery()],
    ReplayCall.findDevice => await _findDevice(driver),
    ReplayCall.pullActivity => await driver.pullActivity(_since),
    ReplayCall.pullHeartRate => await driver.pullHeartRate(_since),
    ReplayCall.pullStress => await driver.pullStress(_since),
    ReplayCall.pullHrv => await driver.pullHrv(_since),
    ReplayCall.pullSpo2 => await driver.pullSpo2(_since),
    ReplayCall.pullSleep => await driver.pullSleep(_since),
  };

  static Future<List<Object>> _syncTime(ColmiDriver driver, DateTime at) async {
    await driver.syncTime(at);
    return [?driver.reportedCapabilities];
  }

  static Future<List<Object>> _findDevice(ColmiDriver driver) async {
    await driver.findDevice();
    return const [];
  }
}

final class _Exchange {
  new(this.request);

  final TraceEntry request;
  final replies = <GattPacket>[];
  bool used = false;
}

// The driver builds its own requests (clock, codec), so a write is matched to
// the recorded exchange with the same body first and the same command second.
final class ReplayScript {
  new(List<TraceEntry> entries) : _exchanges = _split(entries);

  final List<_Exchange> _exchanges;

  Iterable<GattPacket> respond(GattPacket write) {
    final open = _exchanges
        .where(
          (e) => !e.used && _characteristic(e.request) == write.characteristic,
        )
        .toList();
    final bigData = write.characteristic == ColmiDriver.bigDataWrite;
    final exact = bigData ? write.bytes.length : V1Frame.length - 1;
    final command = bigData ? 2 : 1;
    final exchange =
        open
            .where((e) => _samePrefix(e.request.bytes, write.bytes, exact))
            .firstOrNull ??
        open
            .where((e) => _samePrefix(e.request.bytes, write.bytes, command))
            .firstOrNull;
    if (exchange == null) {
      throw BleTransportException(
        'no recorded reply for ${Hex.spaced(write.bytes)}',
      );
    }
    exchange.used = true;
    return exchange.replies;
  }

  static List<_Exchange> _split(List<TraceEntry> entries) {
    final exchanges = <_Exchange>[];
    for (final entry in entries) {
      if (entry.isTx) {
        exchanges.add(_Exchange(entry));
        continue;
      }
      final target = _characteristic(entry);
      final current = exchanges.lastOrNull;
      if (target == null || current == null) continue;
      current.replies.add(GattPacket(target, entry.bytes));
    }
    return exchanges;
  }

  static GattCharacteristic? _characteristic(TraceEntry entry) =>
      switch (entry.channel) {
        TraceChannel.v1Write => ColmiDriver.write,
        TraceChannel.v1Notify => ColmiDriver.notify,
        TraceChannel.bigDataWrite => ColmiDriver.bigDataWrite,
        TraceChannel.bigDataNotify => ColmiDriver.bigDataNotify,
        null => null,
      };
}

bool _samePrefix(List<int> a, List<int> b, int length) {
  if (a.length < length || b.length < length) return false;
  for (var i = 0; i < length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
