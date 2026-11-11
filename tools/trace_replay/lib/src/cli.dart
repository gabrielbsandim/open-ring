import 'dart:io';

import 'package:trace_replay/src/checksum_check.dart';
import 'package:trace_replay/src/describe.dart';
import 'package:trace_replay/src/frame_decoder.dart';
import 'package:trace_replay/src/hex.dart';
import 'package:trace_replay/src/replayer.dart';
import 'package:trace_replay/src/trace.dart';

abstract final class ExitCodes {
  static const ok = 0;
  static const usage = 64;
  static const noInput = 66;
}

const usage = '''
Usage: trace_replay <command> <file.jsonl> [options]

Commands:
  decode <file>   Print every frame with its decoded meaning and checksum rule.
  replay <file>   Feed the recorded replies to ColmiDriver and print its records.

Replay options:
  --checksum masked|mod255   V1 checksum rule for the driver codec.
                             Default: detected from the rx frames.
  --now <ISO-8601>           Driver clock. Without an offset it is local time.
                             Default: each request's time in this machine's zone.
  --timeout <ms>             How long the driver waits for a reply. Default 1000.
''';

const _commandOptions = {
  'decode': <String>{},
  'replay': {'checksum', 'now', 'timeout'},
};

final class _UsageException implements Exception {
  const new(this.message);

  final String message;
}

Future<int> runCli(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) async {
  if (args.isEmpty) {
    err.write(usage);
    return ExitCodes.usage;
  }
  if (const {'help', '--help', '-h'}.contains(args.first)) {
    out.write(usage);
    return ExitCodes.ok;
  }
  try {
    return await _dispatch(args, out, err);
  } on _UsageException catch (e) {
    err
      ..writeln(e.message)
      ..write(usage);
    return ExitCodes.usage;
  }
}

Future<int> _dispatch(List<String> args, StringSink out, StringSink err) async {
  final command = args.first;
  final allowed = _commandOptions[command];
  if (allowed == null) throw _UsageException('Unknown command "$command".');
  if (args.length < 2) throw const _UsageException('Missing the trace file.');
  final options = _options(args.sublist(2));
  final unknown = options.keys.where((key) => !allowed.contains(key));
  if (unknown.isNotEmpty) {
    throw _UsageException('Unknown option --${unknown.first} for $command.');
  }
  final String source;
  try {
    source = await File(args[1]).readAsString();
  } on FileSystemException catch (e) {
    err.writeln('Cannot read ${args[1]}: ${e.osError?.message ?? e.message}');
    return ExitCodes.noInput;
  }
  final lines = Trace.parse(source);
  if (command == 'decode') {
    writeDecode(lines, out);
    return ExitCodes.ok;
  }
  final replayer = TraceReplayer(
    rule: _rule(options['checksum']),
    now: _now(options['now']),
    timeout: _timeout(options['timeout']),
  );
  _writeMalformed(lines, out);
  writeReplay(await replayer.replay(Trace.entries(lines)), out);
  return ExitCodes.ok;
}

void writeDecode(List<TraceLine> lines, StringSink out) {
  final decoder = TraceDecoder();
  final frames = <DecodedFrame>[];
  var malformed = 0;
  for (final line in lines) {
    switch (line) {
      case MalformedLine():
        malformed++;
        _writeMalformedLine(line, out);
      case TraceEntry():
        final frame = decoder.decode(line);
        frames.add(frame);
        _writeFrame(frame, out);
    }
  }
  _writeSummary(frames, malformed, out);
}

void writeReplay(ReplayResult result, StringSink out) {
  final source = result.ruleDetected ? 'detected from the trace' : 'forced';
  out.writeln(
    'replay: ${result.steps.length} steps, checksum rule '
    '${result.rule.label}, $source',
  );
  for (var i = 0; i < result.steps.length; i++) {
    _writeStep(i + 1, result.steps[i], out);
  }
  for (final tx in result.skipped) {
    out.writeln(
      'not replayed: line ${tx.lineNumber} ${Hex.spaced(tx.bytes)} '
      '(no driver call sends it)',
    );
  }
}

void _writeStep(int index, ReplayStep step, StringSink out) {
  final lines = step.requests.map((r) => r.lineNumber).join(', ');
  final count = step.requests.length;
  final days = count == 1 ? '1 day' : '$count days';
  final span = step.call.perDay ? ', $days' : '';
  out.writeln('step $index ${step.call.name} (tx line $lines$span)');
  final error = step.error;
  if (error != null) {
    out.writeln('  FAILED: $error');
    return;
  }
  if (step.records.isEmpty) out.writeln('  ok, no records');
  for (final record in step.records) {
    out.writeln('  ${describeRecord(record)}');
  }
}

void _writeFrame(DecodedFrame frame, StringSink out) {
  final entry = frame.entry;
  final channel = entry.channel?.label ?? 'unknown';
  out.writeln(
    'line ${entry.lineNumber} ${entry.at.toUtc().toIso8601String()} '
    '${entry.direction.name} $channel  ${Hex.spaced(entry.bytes)}',
  );
  final checksum = frame.checksum;
  if (checksum != null) out.writeln('  checksum: ${checksum.describe()}');
  final failure = frame.failure;
  if (failure != null) {
    out.writeln('  FAILED: $failure');
    return;
  }
  out.writeln('  ${frame.meaning}');
}

void _writeMalformed(List<TraceLine> lines, StringSink out) {
  for (final line in lines.whereType<MalformedLine>()) {
    _writeMalformedLine(line, out);
  }
}

void _writeMalformedLine(MalformedLine line, StringSink out) =>
    out.writeln('line ${line.lineNumber} MALFORMED: ${line.reason}');

void _writeSummary(List<DecodedFrame> frames, int malformed, StringSink out) {
  final tx = frames.where((f) => f.entry.isTx).length;
  final failed = frames.where((f) => f.failed).length;
  final tally = ChecksumTally();
  frames.map((f) => f.checksum).nonNulls.forEach(tally.add);
  out
    ..writeln()
    ..writeln(
      'summary: ${frames.length} frames (${frames.length - tx} rx, $tx tx), '
      '$failed failed, $malformed malformed lines',
    )
    ..writeln(
      'v1 checksum over ${tally.total} frames: '
      '${tally[ChecksumMatch.both]} both, '
      '${tally[ChecksumMatch.maskedOnly]} masked only, '
      '${tally[ChecksumMatch.modulo255Only]} modulo 255 only, '
      '${tally[ChecksumMatch.neither]} neither',
    )
    ..writeln('rule satisfied by every v1 frame: ${_verdict(tally)}');
}

String _verdict(ChecksumTally tally) {
  if (tally.total == 0) return 'no v1 frames';
  final rules = tally.consistentRules;
  if (rules.isEmpty) return 'none';
  if (rules.length == ChecksumRule.values.length) {
    return 'both (no frame tells them apart)';
  }
  return rules.single.label;
}

Map<String, String> _options(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      throw _UsageException('Unexpected argument "$arg".');
    }
    final equals = arg.indexOf('=');
    if (equals > 0) {
      options[arg.substring(2, equals)] = arg.substring(equals + 1);
      continue;
    }
    if (i + 1 >= args.length) {
      throw _UsageException('Missing a value for $arg.');
    }
    i++;
    options[arg.substring(2)] = args[i];
  }
  return options;
}

ChecksumRule? _rule(String? flag) {
  if (flag == null) return null;
  final rule = ChecksumRule.fromFlag(flag);
  if (rule == null) {
    throw _UsageException('--checksum must be masked or mod255, got "$flag".');
  }
  return rule;
}

DateTime? _now(String? value) {
  if (value == null) return null;
  final now = DateTime.tryParse(value);
  if (now == null) {
    throw _UsageException('--now is not an ISO-8601 time: "$value".');
  }
  return now.toLocal();
}

Duration _timeout(String? value) {
  if (value == null) return const Duration(seconds: 1);
  final ms = int.tryParse(value);
  if (ms == null || ms <= 0) {
    throw _UsageException(
      '--timeout must be a positive number of ms, got "$value".',
    );
  }
  return Duration(milliseconds: ms);
}
