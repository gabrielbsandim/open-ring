import 'package:meta/meta.dart';

enum AutoMeasurement { heartRate, spo2, stress, hrv }

@immutable
final class AutoMeasurements {
  const new({this.off = const {}});

  static const allOn = AutoMeasurements();

  final Set<AutoMeasurement> off;

  bool isOn(AutoMeasurement measurement) => !off.contains(measurement);

  AutoMeasurements turned(AutoMeasurement measurement, {required bool on}) =>
      AutoMeasurements(
        off: on ? off.difference({measurement}) : {...off, measurement},
      );

  @override
  bool operator ==(Object other) =>
      other is AutoMeasurements &&
      other.off.length == off.length &&
      other.off.containsAll(off);

  @override
  int get hashCode => Object.hashAllUnordered(off);
}
