import 'package:meta/meta.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:ring_driver/ring_driver.dart';

// Not a Bluetooth address, so it can never match a real ring.
const demoDeviceId = 'DEMO-RING-0000';

const demoRing = RingIdentity(
  deviceId: demoDeviceId,
  name: 'R09 Demo',
  model: 'R09',
  firmware: 'demo',
);

@immutable
final class DemoData {
  new({
    required this.pairedAt,
    required this.syncedAt,
    required this.battery,
    required List<ActivityBucket> activity,
    required List<HeartRateSample> heartRate,
    required List<HrvSample> hrv,
    required List<Spo2Sample> spo2,
    required List<StressSample> stress,
    required List<SleepSegment> sleep,
    required List<FinishedWorkout> workouts,
    required List<SyncRun> syncRuns,
    this.identity = demoRing,
  }) : activity = List.unmodifiable(activity),
       heartRate = List.unmodifiable(heartRate),
       hrv = List.unmodifiable(hrv),
       spo2 = List.unmodifiable(spo2),
       stress = List.unmodifiable(stress),
       sleep = List.unmodifiable(sleep),
       workouts = List.unmodifiable(workouts),
       syncRuns = List.unmodifiable(syncRuns);

  final RingIdentity identity;
  final DateTime pairedAt;
  final DateTime syncedAt;
  final BatteryStatus battery;
  final List<ActivityBucket> activity;
  final List<HeartRateSample> heartRate;
  final List<HrvSample> hrv;
  final List<Spo2Sample> spo2;
  final List<StressSample> stress;
  final List<SleepSegment> sleep;
  final List<FinishedWorkout> workouts;
  final List<SyncRun> syncRuns;

  String get deviceId => identity.deviceId;
}
