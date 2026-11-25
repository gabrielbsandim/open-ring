import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Weekly energy lives only on the Week screen and its own screen; these
// sources render Today, the home widgets, notifications and the AI context.
const _roots = [
  'lib/features/today',
  'lib/features/widgets',
  'lib/features/ai',
  'android/app/src/main',
  '../../packages/ring_notifications/lib',
  '../../packages/ring_notifications/android',
];

final _energy = RegExp(
  'foodEnergy|food_energy|weekly ?energy',
  caseSensitive: false,
);

Iterable<File> _files(String root) =>
    Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => RegExp(r'\.(dart|kt|java|xml)$').hasMatch(f.path));

void main() {
  test('every scanned root exists', () {
    for (final root in _roots) {
      expect(Directory(root).existsSync(), isTrue, reason: root);
    }
  });

  test('Today, widgets, notifications and the AI context never name Weekly '
      'energy', () {
    final notificationFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().contains('notif'));
    final files = [
      for (final root in _roots) ..._files(root),
      ...notificationFiles,
    ];
    expect(files, isNotEmpty);
    for (final file in files) {
      expect(
        file.readAsStringSync().contains(_energy),
        isFalse,
        reason: file.path,
      );
    }
  });
}
