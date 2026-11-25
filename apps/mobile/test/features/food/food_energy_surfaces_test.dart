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

final _foodImport = RegExp("import 'package:open_ring/(features/food/[^']+)'");

// The queue reads the Weekly energy gate to pick the items schema (DECIDED
// 22); a provider may name the gate but must never reach its strings.
final _energyText = RegExp(r'\.foodEnergy[A-Z]');

bool _isFoodLogic(File file) =>
    file.path.startsWith('lib/features/food/') &&
    !file.path.startsWith('lib/features/food/presentation/');

/// The food files [entry] imports, and the files those food widgets import in
/// turn, so whatever Today or a widget renders from Food is scanned. Imports
/// of food providers are scanned but not followed into the queue and stores.
List<File> _foodImports(List<File> entry) {
  final seen = <String>{};
  final queue = [...entry];
  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    if (!file.path.endsWith('.dart')) continue;
    if (_isFoodLogic(file)) continue;
    for (final m in _foodImport.allMatches(file.readAsStringSync())) {
      final path = 'lib/${m.group(1)}';
      if (seen.add(path)) queue.add(File(path));
    }
  }
  return [for (final path in seen) File(path)];
}

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
    final entry = [
      for (final root in _roots) ..._files(root),
      ...notificationFiles,
    ];
    final food = _foodImports(entry);
    expect(
      food.map((f) => f.path),
      containsAll([
        'lib/features/food/presentation/food_row.dart',
        'lib/features/food/application/today_meals.dart',
      ]),
    );
    final files = [...entry, ...food];
    expect(files, isNotEmpty);
    for (final file in files) {
      expect(
        file.readAsStringSync().contains(
          _isFoodLogic(file) ? _energyText : _energy,
        ),
        isFalse,
        reason: file.path,
      );
    }
  });
}
