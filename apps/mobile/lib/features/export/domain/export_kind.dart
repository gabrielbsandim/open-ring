enum ExportFormat { csv, json }

enum ExportKind {
  sleep('sleep', [
    'session_start',
    'start',
    'end',
    'device_id',
    'stage',
    'duration_s',
  ]),
  heartRate('heart_rate', ['time', 'device_id', 'bpm']),
  hrv('hrv', ['time', 'device_id', 'hrv_ms']),
  spo2('spo2', ['time', 'device_id', 'spo2_percent']),
  stress('stress', ['time', 'device_id', 'stress_level']),
  activity('activity', [
    'start',
    'end',
    'device_id',
    'steps',
    'distance_m',
    'active_kcal',
  ]),
  workouts('workouts', [
    'start',
    'end',
    'client_id',
    'device_id',
    'activity_type',
    'duration_s',
    'distance_m',
    'active_kcal',
  ]);

  new(this.key, this.columns);

  final String key;
  final List<String> columns;
}
