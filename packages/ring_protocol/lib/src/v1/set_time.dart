import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ring_protocol/src/bytes.dart';
import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

abstract final class RingLanguage {
  static const chinese = 0;
  static const english = 1;
}

Uint8List setTimeRequest(
  DateTime time, {
  int language = RingLanguage.english,
  V1FrameCodec codec = const V1FrameCodec(),
}) {
  if (time.year < 2000 || time.year > 2099) {
    throw ArgumentError.value(time.year, 'time', 'year must be 2000..2099');
  }
  return codec.encode(V1Command.setDateTime, [
    toBcd(time.year % 100),
    toBcd(time.month),
    toBcd(time.day),
    toBcd(time.hour),
    toBcd(time.minute),
    toBcd(time.second),
    language,
  ]);
}

@immutable
final class DeviceCapabilities {
  const new({
    required this.supportsTemperature,
    required this.supportsBloodOxygen,
    required this.supportsBloodPressure,
    required this.newSleepProtocol,
    required this.supportsManualHeartRate,
    required this.supportsBloodSugar,
    required this.supportsPressure,
    required this.supportsHrv,
  });

  final bool supportsTemperature;
  final bool supportsBloodOxygen;
  final bool supportsBloodPressure;
  final bool newSleepProtocol;
  final bool supportsManualHeartRate;
  final bool supportsBloodSugar;
  final bool supportsPressure;
  final bool supportsHrv;

  @override
  bool operator ==(Object other) =>
      other is DeviceCapabilities &&
      other.supportsTemperature == supportsTemperature &&
      other.supportsBloodOxygen == supportsBloodOxygen &&
      other.supportsBloodPressure == supportsBloodPressure &&
      other.newSleepProtocol == newSleepProtocol &&
      other.supportsManualHeartRate == supportsManualHeartRate &&
      other.supportsBloodSugar == supportsBloodSugar &&
      other.supportsPressure == supportsPressure &&
      other.supportsHrv == supportsHrv;

  @override
  int get hashCode => Object.hash(
    supportsTemperature,
    supportsBloodOxygen,
    supportsBloodPressure,
    newSleepProtocol,
    supportsManualHeartRate,
    supportsBloodSugar,
    supportsPressure,
    supportsHrv,
  );
}

ParseResult<DeviceCapabilities> parseSetTime(V1Frame frame) {
  final error = commandError(frame, V1Command.setDateTime.id);
  if (error != null) return ParseFailure(error);
  final b = frameBytes(frame);
  return Parsed(
    DeviceCapabilities(
      supportsTemperature: b[1] == 1,
      supportsBloodOxygen: b[4] & 0x02 != 0,
      supportsBloodPressure: b[4] & 0x04 != 0,
      newSleepProtocol: b[9] == 1,
      supportsManualHeartRate: b[12] & 0x01 != 0,
      supportsBloodSugar: b[12] & 0x80 != 0,
      supportsPressure: b[14] & 0x10 != 0,
      supportsHrv: b[14] & 0x20 != 0,
    ),
  );
}
