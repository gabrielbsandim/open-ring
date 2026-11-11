import 'dart:convert';
import 'dart:io';

const usage = '''
dart tool/release_version.dart [--bump auto|patch|minor|major]
                               [--version X.Y.Z] [--notes-file <path>]

Derives the next release version and its notes from the Conventional Commits
since the last v* tag that change what ships in the app. Prints a JSON summary
on stdout, or exits 2 when no such commit exists.''';

const sections = [
  ('feat', 'Features'),
  ('fix', 'Bug Fixes'),
  ('perf', 'Performance'),
  ('refactor', 'Refactoring'),
  ('docs', 'Documentation'),
  ('build', 'Build & Dependencies'),
  ('ci', 'CI/CD'),
  ('test', 'Tests'),
  ('style', 'Styling'),
  ('chore', 'Chores'),
  ('revert', 'Reverts'),
];

const bumps = ['auto', 'patch', 'minor', 'major'];

// Relative to apps/mobile, where the tool runs. Tests, tools and docs change no
// install, so a commit that only touches them is not an app release.
const appPaths = [
  'lib',
  'android',
  'ios',
  'assets',
  '../../packages',
  'pubspec.yaml',
  'pubspec.lock',
  'l10n.yaml',
  'shorebird.yaml',
];

// The version bump and the release merge sit inside the next range; listing
// them as changes would make every release note mention the previous release.
final bookkeeping = RegExp(r'^(?:build: release|release:) v\d+\.\d+\.\d+$');
final subjectPattern = RegExp(
  r'^(?<type>[a-z]+)(?:\((?<scope>[^)]*)\))?(?<bang>!)?: (?<rest>.+)$',
);
final breakingInBody = RegExp('^BREAKING[ -]CHANGE:', multiLine: true);
final pubspecVersion = RegExp(
  r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
  multiLine: true,
);
final bareVersion = RegExp(r'^\d+\.\d+\.\d+$');

final class Commit {
  const new({
    required this.hash,
    required this.subject,
    required this.description,
    this.type,
    this.scope,
    this.breaking = false,
  });

  factory parse(String record) {
    final fields = record.split('\x1f');
    final hash = fields[0];
    final subject = fields.length > 1 ? fields[1] : '';
    final body = fields.length > 2 ? fields[2] : '';
    final match = subjectPattern.firstMatch(subject);
    if (match == null) {
      return Commit(hash: hash, subject: subject, description: subject);
    }
    return Commit(
      hash: hash,
      subject: subject,
      description: match.namedGroup('rest')!,
      type: match.namedGroup('type'),
      scope: match.namedGroup('scope'),
      breaking:
          match.namedGroup('bang') != null || breakingInBody.hasMatch(body),
    );
  }

  final String hash;
  final String subject;
  final String description;
  final String? type;
  final String? scope;
  final bool breaking;

  String get line {
    final prefix = scope == null ? '' : '**$scope:** ';
    return '- $prefix$description (${hash.substring(0, 7)})';
  }
}

String git(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) {
    stderr.writeln('git ${args.join(' ')} failed: ${result.stderr}');
    exit(1);
  }
  return (result.stdout as String).trim();
}

String? option(List<String> args, String name) {
  final index = args.indexOf('--$name');
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String? lastTag() {
  final tags = git(['tag', '--list', 'v[0-9]*', '--sort=-v:refname']);
  if (tags.isEmpty) return null;
  return tags.split('\n').first;
}

(String, int) readPubspecVersion() {
  final match = pubspecVersion.firstMatch(
    File('pubspec.yaml').readAsStringSync(),
  );
  if (match == null) {
    stderr.writeln('pubspec.yaml has no "version: X.Y.Z+N" line.');
    exit(1);
  }
  return (match.group(1)!, int.parse(match.group(2)!));
}

List<Commit> parseCommits(String range) {
  final raw = git([
    'log',
    '--format=%H%x1f%s%x1f%b%x1e',
    range,
    '--',
    ...appPaths,
  ]);
  return raw
      .split('\x1e')
      .map((record) => record.replaceFirst(RegExp(r'^\n'), ''))
      .where((record) => record.isNotEmpty)
      .map(Commit.parse)
      .toList();
}

String detectBump(List<Commit> commits) {
  if (commits.any((commit) => commit.breaking)) return 'major';
  if (commits.any((commit) => commit.type == 'feat')) return 'minor';
  return 'patch';
}

// 0.x reads a breaking change as a minor, so 1.0.0 stays a decision rather
// than the side effect of a stray `!`.
String applyBump(String version, String bump) {
  final [major, minor, patch] = version.split('.').map(int.parse).toList();
  final effective = bump == 'major' && major == 0 ? 'minor' : bump;
  return switch (effective) {
    'major' => '${major + 1}.0.0',
    'minor' => '$major.${minor + 1}.0',
    _ => '$major.$minor.${patch + 1}',
  };
}

String renderNotes(List<Commit> commits, String version, String previous) {
  final lines = ['## v$version', ''];
  final breaking = commits.where((commit) => commit.breaking).toList();
  if (breaking.isNotEmpty) {
    lines.addAll([
      '### Breaking Changes',
      '',
      ...breaking.map((c) => c.line),
      '',
    ]);
  }

  for (final (type, heading) in sections) {
    final group = commits.where((c) => c.type == type && !c.breaking).toList();
    if (group.isEmpty) continue;
    lines.addAll(['### $heading', '', ...group.map((c) => c.line), '']);
  }

  final known = sections.map((section) => section.$1).toSet();
  final leftover = commits
      .where((c) => !c.breaking && !known.contains(c.type))
      .toList();
  if (leftover.isNotEmpty) {
    lines.addAll(['### Uncategorised', '', ...leftover.map((c) => c.line), '']);
  }

  lines.addAll(['**Full diff:** `v$previous`...`v$version`', '']);
  return lines.join('\n');
}

void main(List<String> args) {
  if (args.contains('--help')) {
    stdout.writeln(usage);
    return;
  }

  final requested = option(args, 'bump') ?? 'auto';
  if (!bumps.contains(requested)) {
    stderr.writeln('Unknown --bump "$requested". Use ${bumps.join(', ')}.');
    exit(1);
  }

  final pinned = option(args, 'version');
  if (pinned != null && !bareVersion.hasMatch(pinned)) {
    stderr.writeln('--version "$pinned" is not a bare X.Y.Z version.');
    exit(1);
  }

  final (current, build) = readPubspecVersion();
  final tag = lastTag();
  if (tag == null) {
    stderr.writeln(
      [
        'No v* tag found, so there is no boundary for the release notes.',
        '',
        'Create the baseline once, on the commit main is at (v$current):',
        '',
        '  git tag v$current origin/main',
        '  git push origin v$current',
      ].join('\n'),
    );
    exit(3);
  }

  final range = '$tag..HEAD';
  final commits = parseCommits(range)
      .where((commit) => !bookkeeping.hasMatch(commit.subject))
      .toList();
  if (commits.isEmpty) {
    stderr.writeln('No app change in $range. Nothing to release.');
    exit(2);
  }

  final previous = tag.substring(1);
  final bump = requested == 'auto' ? detectBump(commits) : requested;
  final version = pinned ?? applyBump(previous, bump);
  final nextBuild = current == version ? build : build + 1;

  final notesFile = option(args, 'notes-file');
  if (notesFile != null) {
    File(notesFile)
        .writeAsStringSync('${renderNotes(commits, version, previous)}\n');
  }

  stdout.writeln(
    jsonEncode({
      'version': version,
      'build': nextBuild,
      'tag': 'v$version',
      'previous': previous,
      'bump': bump,
      'range': range,
      'commits': commits.length,
    }),
  );
}
