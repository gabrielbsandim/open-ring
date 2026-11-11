import 'dart:io';

const usage = '''
dart tool/store_notes.dart [--since <tag>]

Checks the Play "What's new" files in distribution/whatsnew: one per locale,
none blank or over the Play limit and, with --since, each changed after that
tag.''';

const directory = 'distribution/whatsnew';
const locales = [
  'de-DE',
  'en-US',
  'es-ES',
  'fr-FR',
  'id',
  'it-IT',
  'ja-JP',
  'pt-BR',
  'pt-PT',
  'ru-RU',
  'zh-CN',
];
const limit = 500;

String? noteProblem(String locale, String? text) => switch (text) {
  null => 'whatsnew-$locale is missing.',
  final String body when body.trim().isEmpty => 'whatsnew-$locale is blank.',
  final String body when body.runes.length > limit =>
    'whatsnew-$locale has ${body.runes.length} characters, Play takes $limit.',
  _ => null,
};

String? readNote(String locale) {
  final file = File('$directory/whatsnew-$locale');
  return file.existsSync() ? file.readAsStringSync() : null;
}

// git diff --quiet exits 1 when the file differs, and anything above 1 is an error.
String? staleProblem(String tag, String locale, {String? root}) {
  final result = Process.runSync('git', [
    'diff',
    '--quiet',
    tag,
    'HEAD',
    '--',
    '$directory/whatsnew-$locale',
  ], workingDirectory: root);
  return switch (result.exitCode) {
    0 => 'whatsnew-$locale is unchanged since $tag. Write it on develop.',
    1 => null,
    _ => 'git diff against $tag failed: ${result.stderr}',
  };
}

List<String> sinceProblems(List<String> args, {String? root}) {
  final index = args.indexOf('--since');
  if (index == -1) return [];
  final tag = args.elementAtOrNull(index + 1);
  if (tag == null) return ['--since needs a tag.'];
  return [for (final locale in locales) ?staleProblem(tag, locale, root: root)];
}

void main(List<String> args) {
  if (args.contains('--help')) {
    stdout.writeln(usage);
    return;
  }

  final problems = [
    for (final locale in locales) ?noteProblem(locale, readNote(locale)),
    ...sinceProblems(args),
  ];
  if (problems.isEmpty) {
    stdout.writeln('The Play notes for ${locales.length} locales are ready.');
    return;
  }
  stderr.writeln(problems.join('\n'));
  exit(1);
}
