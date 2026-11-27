import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A file that reaches the workouts table must skip open rows (end_utc_ms
// null). Add a new one here only with a reader case in the checkpoint tests.
const workoutsTableFiles = {
  'lib/core/database/app_database.dart': 'migrations',
  'lib/features/demo/infrastructure/drift_demo_data_store.dart':
      'demo replace and wipe',
  'lib/features/export/infrastructure/export_pages_dao.dart':
      'export of the workouts kind',
  'lib/features/health_sync/infrastructure/drift_health_record_source.dart':
      'health source workout batch and heart rate windows',
  'lib/features/workout/infrastructure/drift_workout_rating_store.dart':
      'ratings, an open row has none',
  'lib/features/workout/infrastructure/workouts_dao.dart':
      'recent, intersecting, byId, routed, checkpoint and save',
};

final _access = [
  RegExp(r'\b\w*(?:db|Db|database|Database|schema)\.workouts\b'),
  RegExp(r'@DriftAccessor\(\s*tables:\s*\[[^\]]*\bWorkouts\b'),
  RegExp(
    r'''['"][^'"]*\b(?:from|join|into|update)\s+workouts\b''',
    caseSensitive: false,
  ),
];

bool touchesWorkouts(String source) =>
    _access.any((pattern) => pattern.hasMatch(source));

void main() {
  test('the census pattern tells table access from other workouts', () {
    expect(touchesWorkouts('await (_db.select(_db.workouts)).get();'), isTrue);
    expect(touchesWorkouts('final table = attachedDatabase.workouts;'), isTrue);
    expect(touchesWorkouts('final w = schema.workouts;'), isTrue);
    expect(
      touchesWorkouts(
        '@DriftAccessor(\n  tables: [Workouts, WorkoutHrSamples],\n)',
      ),
      isTrue,
    );
    expect(
      touchesWorkouts("customSelect('SELECT COUNT(*) FROM workouts')"),
      isTrue,
    );
    expect(touchesWorkouts('...imported.workouts,'), isFalse);
    expect(touchesWorkouts('EnergyPart.workouts => day.workouts,'), isFalse);
    expect(
      touchesWorkouts('@DriftAccessor(tables: [ImportedWorkouts])'),
      isFalse,
    );
  });

  test('the files under lib that reach the workouts table are the pinned '
      'list', () {
    final found = <String>{
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart') &&
            !entity.path.endsWith('.steps.dart') &&
            touchesWorkouts(entity.readAsStringSync()))
          entity.path.replaceAll(r'\', '/'),
    };

    expect(found, workoutsTableFiles.keys.toSet());
  });
}
