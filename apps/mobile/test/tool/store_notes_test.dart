import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/store_notes.dart';

void main() {
  test('takes a note within the Play limit', () {
    expect(noteProblem('pt-BR', 'Novidades.\n'), isNull);
  });

  test('reports a missing note', () {
    expect(noteProblem('en-US', null), 'whatsnew-en-US is missing.');
  });

  test('reports a note that is only whitespace', () {
    expect(noteProblem('pt-BR', ' \n\t'), 'whatsnew-pt-BR is blank.');
  });

  test('takes a note of exactly the limit and refuses one over it', () {
    expect(noteProblem('pt-BR', 'ç' * limit), isNull);
    expect(
      noteProblem('pt-BR', 'ç' * (limit + 1)),
      'whatsnew-pt-BR has ${limit + 1} characters, Play takes $limit.',
    );
  });

  test('every locale of the repository has a valid note', () {
    for (final locale in locales) {
      expect(noteProblem(locale, readNote(locale)), isNull);
    }
  });

  group('since a tag', () {
    late Directory repo;

    void git(List<String> args) {
      final result = Process.runSync('git', [
        '-c',
        'user.name=openring',
        '-c',
        'user.email=openring@openring.test',
        ...args,
      ], workingDirectory: repo.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    void writeNotes(String text, {Iterable<String> only = locales}) {
      for (final locale in only) {
        File('${repo.path}/$directory/whatsnew-$locale')
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      }
      git(['add', '.']);
      git(['commit', '-qm', 'docs: notes']);
    }

    setUp(() {
      repo = Directory.systemTemp.createTempSync('store_notes');
      git(['init', '-q']);
      writeNotes('v1');
      git(['tag', 'v1.0.0']);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('reports every note left as it was at the tag', () {
      expect(
        sinceProblems(['--since', 'v1.0.0'], root: repo.path),
        hasLength(locales.length),
      );
    });

    test('reports the one locale that was not rewritten', () {
      writeNotes('v2', only: locales.skip(1));
      final problems = sinceProblems(['--since', 'v1.0.0'], root: repo.path);
      expect(
        problems.single,
        contains('whatsnew-${locales.first} is unchanged'),
      );
    });

    test('takes notes rewritten after the tag', () {
      writeNotes('v2');
      expect(sinceProblems(['--since', 'v1.0.0'], root: repo.path), isEmpty);
    });

    test('reports a git failure instead of reading it as a change', () {
      final problems = sinceProblems(['--since', 'v9.9.9'], root: repo.path);
      expect(problems.first, startsWith('git diff against v9.9.9 failed'));
    });

    test('reports --since without a tag and skips the check without it', () {
      expect(sinceProblems(['--since'], root: repo.path), [
        '--since needs a tag.',
      ]);
      expect(sinceProblems([], root: repo.path), isEmpty);
    });
  });
}
