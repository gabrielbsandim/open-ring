import 'package:ring_driver/ring_driver.dart';
import 'package:ring_protocol/ring_protocol.dart';
import 'package:trace_replay/src/hex.dart';

String? commandName(int command) =>
    v1CommandStatus[command]?.name ?? V1Command.fromId(command)?.name;

String? bigDataName(int dataId) => bigDataStatus[dataId]?.name;

String describeError(ParseError error) => switch (error) {
  WrongLength(:final expected, :final actual) =>
    'wrong length: expected $expected bytes, got $actual',
  ByteOutOfRange(:final index, :final value) =>
    'byte $index has an unexpected value ${Hex.id(value)}',
  ChecksumMismatch(:final expected, :final actual) =>
    'checksum mismatch: expected ${Hex.word(expected)}, got ${Hex.word(actual)}',
  UnexpectedCommand(:final expected, :final actual) =>
    'unexpected id: expected ${Hex.id(expected)}, got ${Hex.id(actual)}',
  ErrorResponse(:final command) =>
    'error response ${Hex.id(command)} (bit 7 set)',
};

String describeCapabilities(DeviceCapabilities c) {
  final supported = [
    if (c.supportsTemperature) 'temperature',
    if (c.supportsBloodOxygen) 'blood oxygen',
    if (c.supportsBloodPressure) 'blood pressure',
    if (c.supportsManualHeartRate) 'manual heart rate',
    if (c.supportsBloodSugar) 'blood sugar',
    if (c.supportsPressure) 'pressure',
    if (c.supportsHrv) 'hrv',
    if (c.newSleepProtocol) 'new sleep protocol',
  ];
  if (supported.isEmpty) return 'no capability flags set';
  return supported.join(', ');
}

String describeBattery(BatteryReading reading) =>
    '${reading.percent}%, ${_charging(reading.charging)}';

String describeSlotLog(SlotLog log) {
  final set = [
    for (var i = 0; i < log.values.length; i++)
      if (log.values[i] != 0)
        '${clockTime(i * log.intervalMinutes)}=${log.values[i]}',
  ];
  final reported = log.reportedSeconds;
  final day = reported == null ? '' : ', day ${_utcDay(reported)}';
  final head =
      '${log.values.length} slots every ${log.intervalMinutes} min$day, '
      '${set.length} set';
  if (set.isEmpty) return head;
  return '$head: ${set.join(' ')}';
}

String describeActivity(List<ActivityRecord> records) {
  if (records.isEmpty) return 'no activity records';
  return records
      .map(
        (r) =>
            '${r.year}-${_two(r.month)}-${_two(r.day)} '
            '${clockTime(r.minuteOfDay)} ${r.steps} steps, '
            '${r.distanceMeters} m, ${r.calories} cal',
      )
      .join('; ');
}

String describeTodayTotals(TodayTotals t) =>
    '${t.totalSteps} steps (${t.runningSteps} running), ${t.calories} cal, '
    '${t.walkingDistanceMeters} m, ${t.activeMinutes} active min';

String describeNotification(DeviceNotification n) => switch (n) {
  NewDataAvailable(:final type) => 'new data available, type ${Hex.id(type)}',
  BatteryNotification(:final percent, :final charging) =>
    'battery push $percent%, ${_charging(charging)}',
  LiveActivityNotification(
    :final steps,
    :final calories,
    :final distanceMeters,
  ) =>
    'live activity $steps steps, $calories cal, $distanceMeters m',
  TemperatureNotification(:final provisionalCelsius, :final raw) =>
    'temperature push ${provisionalCelsius ?? 'no value'} (provisional), raw ${Hex.spaced(raw)}',
  UnknownNotification(:final type, :final raw) =>
    'unknown notification type ${Hex.id(type)}, raw ${Hex.spaced(raw)}',
};

String describeRealTime(RealTimeReading r) {
  final status = r.isError ? 'error code ${r.errorCode}' : 'value ${r.value}';
  return 'real time ${r.type.name} $status';
}

String describeSleep(List<SleepDay> days) {
  if (days.isEmpty) return 'no sleep';
  return days
      .map(
        (d) =>
            'days ago ${d.daysAgo}: ${clockTime(d.startMinute)} to '
            '${clockTime(d.endMinute)}, '
            '${d.periods.map((p) => '${_stage(p.stage)} ${p.minutes} min').join(', ')}',
      )
      .join('; ');
}

String describeSpo2(List<Spo2Day> days) {
  if (days.isEmpty) return 'no SpO2';
  return days
      .map((d) {
        final hours = [
          for (var h = 0; h < d.hourly.length; h++)
            if (d.hourly[h].hasData)
              '${_two(h)}h=${d.hourly[h].min}-${d.hourly[h].max}',
        ];
        return 'days ago ${d.daysAgo}: ${hours.length} hours with data'
            '${hours.isEmpty ? '' : ': ${hours.join(' ')}'}';
      })
      .join('; ');
}

String describeTemperature(List<TemperatureDay> days) {
  if (days.isEmpty) return 'no temperature';
  return days
      .map((d) {
        final slots = [
          for (var i = 0; i < d.halfHourly.length; i++)
            if (d.halfHourly[i] case final double celsius)
              '${clockTime(i * 30)}=${celsius.toStringAsFixed(1)}C',
        ];
        return 'days ago ${d.daysAgo}: ${slots.length} slots with data'
            '${slots.isEmpty ? '' : ': ${slots.join(' ')}'}';
      })
      .join('; ');
}

String describeRecord(Object record) => switch (record) {
  final DeviceCapabilities c => 'capabilities: ${describeCapabilities(c)}',
  BatteryStatus(:final percent, :final charging) =>
    'battery $percent%, ${_charging(charging)}',
  ActivityBucket() =>
    '${stamp(record.start)} +${record.duration.inMinutes} min  '
        '${record.steps} steps, ${record.distanceMeters} m, '
        '${record.activeKilocalories.toStringAsFixed(2)} kcal',
  HeartRateSample(:final at, :final bpm) => '${stamp(at)}  heart rate $bpm bpm',
  Spo2Sample(:final at, :final percent) => '${stamp(at)}  SpO2 $percent%',
  StressSample(:final at, :final level) => '${stamp(at)}  stress $level',
  HrvSample(:final at, :final milliseconds) =>
    '${stamp(at)}  HRV $milliseconds ms',
  SleepSegment(:final start, :final end, :final stage) =>
    '${stamp(start)} to ${stamp(end)}  sleep ${stage.name}',
  _ => record.toString(),
};

String stamp(DateTime at) =>
    '${at.year}-${_two(at.month)}-${_two(at.day)} '
    '${_two(at.hour)}:${_two(at.minute)}';

String clockTime(int minutes) {
  final sign = minutes < 0 ? '-' : '';
  final value = minutes.abs();
  return '$sign${_two(value ~/ 60)}:${_two(value % 60)}';
}

String _charging(bool charging) => charging ? 'charging' : 'not charging';

String _utcDay(int seconds) {
  final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  return '${at.year}-${_two(at.month)}-${_two(at.day)}';
}

String _stage(int code) => switch (code) {
  SleepStageCode.noData => 'no data',
  SleepStageCode.error => 'error',
  SleepStageCode.light => 'light',
  SleepStageCode.deep => 'deep',
  SleepStageCode.rem => 'rem',
  SleepStageCode.awake => 'awake',
  _ => 'stage $code',
};

String _two(int value) => value.toString().padLeft(2, '0');
