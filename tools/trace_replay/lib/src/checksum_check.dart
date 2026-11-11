import 'package:meta/meta.dart';
import 'package:ring_protocol/ring_protocol.dart';
import 'package:trace_replay/src/hex.dart';
import 'package:trace_replay/src/trace.dart';

enum ChecksumRule {
  masked(MaskedSumChecksum(), 'masked (& 0xFF)', 'masked'),
  modulo255(Modulo255SumChecksum(), 'modulo 255 (% 255)', 'mod255');

  new(this.strategy, this.label, this.flag);

  final ChecksumStrategy strategy;
  final String label;
  final String flag;

  V1FrameCodec get codec => V1FrameCodec(checksum: strategy);

  static ChecksumRule? fromFlag(String flag) {
    for (final rule in values) {
      if (rule.flag == flag) return rule;
    }
    return null;
  }
}

enum ChecksumMatch { both, maskedOnly, modulo255Only, neither }

@immutable
final class ChecksumCheck {
  const new({
    required this.masked,
    required this.modulo255,
    required this.actual,
  });

  factory of(List<int> frame) {
    if (frame.length != V1Frame.length) {
      throw ArgumentError.value(frame.length, 'frame', 'must be 16 bytes');
    }
    final body = frame.sublist(0, V1Frame.length - 1);
    return ChecksumCheck(
      masked: ChecksumRule.masked.strategy.compute(body),
      modulo255: ChecksumRule.modulo255.strategy.compute(body),
      actual: frame.last,
    );
  }

  final int masked;
  final int modulo255;
  final int actual;

  ChecksumMatch get match => switch ((actual == masked, actual == modulo255)) {
    (true, true) => ChecksumMatch.both,
    (true, false) => ChecksumMatch.maskedOnly,
    (false, true) => ChecksumMatch.modulo255Only,
    (false, false) => ChecksumMatch.neither,
  };

  ChecksumRule? get satisfiedRule => switch (match) {
    ChecksumMatch.both || ChecksumMatch.maskedOnly => ChecksumRule.masked,
    ChecksumMatch.modulo255Only => ChecksumRule.modulo255,
    ChecksumMatch.neither => null,
  };

  String describe() => switch (match) {
    ChecksumMatch.both => 'ok under both rules (${Hex.id(actual)})',
    ChecksumMatch.maskedOnly =>
      'masked only (${Hex.id(actual)}; modulo 255 expects ${Hex.id(modulo255)})',
    ChecksumMatch.modulo255Only =>
      'modulo 255 only (${Hex.id(actual)}; masked expects ${Hex.id(masked)})',
    ChecksumMatch.neither =>
      'MISMATCH under both rules: frame has ${Hex.id(actual)}, '
          'masked expects ${Hex.id(masked)}, '
          'modulo 255 expects ${Hex.id(modulo255)}',
  };
}

final class ChecksumTally {
  final Map<ChecksumMatch, int> _counts = {
    for (final match in ChecksumMatch.values) match: 0,
  };

  int operator [](ChecksumMatch match) => _counts[match]!;

  int get total => _counts.values.fold(0, (sum, count) => sum + count);

  void add(ChecksumCheck check) => _counts[check.match] = this[check.match] + 1;

  Set<ChecksumRule> get consistentRules {
    if (total == 0 || this[ChecksumMatch.neither] > 0) return const {};
    return {
      if (this[ChecksumMatch.modulo255Only] == 0) ChecksumRule.masked,
      if (this[ChecksumMatch.maskedOnly] == 0) ChecksumRule.modulo255,
    };
  }

  ChecksumRule get likelyRule =>
      this[ChecksumMatch.modulo255Only] > this[ChecksumMatch.maskedOnly]
      ? ChecksumRule.modulo255
      : ChecksumRule.masked;

  static ChecksumTally ofEntries(
    Iterable<TraceEntry> entries, {
    TraceDirection? direction,
  }) {
    final tally = ChecksumTally();
    for (final entry in entries) {
      if (direction != null && entry.direction != direction) continue;
      if (entry.channel?.isBigData ?? true) continue;
      if (entry.bytes.length != V1Frame.length) continue;
      tally.add(ChecksumCheck.of(entry.bytes));
    }
    return tally;
  }
}
