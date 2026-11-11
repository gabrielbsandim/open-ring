import 'package:open_ring/core/records/record_kind.dart';

enum HealthRecordKind {
  activity,
  heartRate,
  spo2,
  stress,
  hrv,
  sleep,
  workout;

  static HealthRecordKind ofRing(RecordKind kind) => switch (kind) {
    RecordKind.activity => activity,
    RecordKind.heartRate => heartRate,
    RecordKind.spo2 => spo2,
    RecordKind.stress => stress,
    RecordKind.hrv => hrv,
    RecordKind.sleep => sleep,
  };

  // Neither Health Connect nor HealthKit has a stress type to write into.
  bool get hasPlatformType => this != stress;
}

enum OutboxStatus { pending, done, dead, notApplicable, disabled }
