enum WorkoutLocation { outdoor, optional, indoor }

enum WorkoutType {
  running(activityType: 'running', location: WorkoutLocation.outdoor, met: 9.8),
  walking(activityType: 'walking', location: WorkoutLocation.outdoor, met: 3.5),
  cycling(activityType: 'cycling', location: WorkoutLocation.outdoor, met: 7.5),
  hiking(activityType: 'hiking', location: WorkoutLocation.outdoor, met: 6),
  strength(
    activityType: 'strength_training',
    location: WorkoutLocation.indoor,
    met: 3.5,
  ),
  treadmill(
    activityType: 'treadmill_running',
    location: WorkoutLocation.indoor,
    met: 9.8,
  ),
  stationaryBike(
    activityType: 'stationary_cycling',
    location: WorkoutLocation.indoor,
    met: 7,
  ),
  elliptical(
    activityType: 'elliptical',
    location: WorkoutLocation.indoor,
    met: 5,
  ),
  yoga(activityType: 'yoga', location: WorkoutLocation.indoor, met: 2.5),
  other(activityType: 'other', location: WorkoutLocation.optional, met: 4);

  new({required this.activityType, required this.location, required this.met});

  final String activityType;
  final WorkoutLocation location;
  final double met;

  bool get gpsByDefault => location == WorkoutLocation.outdoor;

  bool get gpsChoosable => location != WorkoutLocation.indoor;

  bool allowsGps({required bool requested}) => requested && gpsChoosable;

  static WorkoutType ofActivityType(String activityType) => values.firstWhere(
    (type) => type.activityType == activityType,
    orElse: () => other,
  );
}
