import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// AI-1: readings appear on their own screen and the Histórico row only, never
// on Today, home screen widgets or notifications.
const _guarded = [
  'lib/features/today',
  'lib/features/widgets',
  'lib/app/background',
  'lib/features/ring/domain/ring_alerts.dart',
  'lib/features/ring/application/sync_alerts.dart',
  'lib/features/ring/application/ring_alert_providers.dart',
  'lib/features/ring/infrastructure/method_channel_ring_notifier.dart',
  'lib/features/workout/domain/workout_notifier.dart',
  'lib/features/workout/application/workout_alert_providers.dart',
  'lib/features/workout/infrastructure/method_channel_workout_notifier.dart',
];

final _aiUse = RegExp(r'features/ai/|\bl10n\.ai[A-Z]|\.aiHistoryRow\b');

List<File> _files(String path) {
  if (FileSystemEntity.isFileSync(path)) return [File(path)];
  return [
    for (final e in Directory(path).listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e,
  ];
}

void main() {
  test('Today, widgets and notifications hold no AI text or AI code', () {
    final hits = <String>[];
    for (final path in _guarded) {
      final files = _files(path);
      expect(files, isNotEmpty, reason: '$path moved; update the guard');
      for (final f in files) {
        if (_aiUse.hasMatch(f.readAsStringSync())) hits.add(f.path);
      }
    }
    expect(hits, isEmpty);
  });

  test('only Histórico places the AI readings row', () {
    final users = [
      for (final f in _files('lib'))
        if (!f.path.contains('/features/ai/') &&
            f.readAsStringSync().contains('ai_history_row.dart'))
          f.path,
    ];
    expect(users, ['lib/features/trends/presentation/trends_screen.dart']);
  });
}
