import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';
import 'package:trace_replay/trace_replay.dart';

import 'helpers.dart';

void main() {
  group('ChecksumCheck', () {
    test('a sum under 255 satisfies both rules', () {
      final check = ChecksumCheck.of(
        hex('03 50 01 00 00 00 00 00 00 00 00 00 00 00 00 54'),
      );

      expect(check.match, ChecksumMatch.both);
      expect(check.satisfiedRule, ChecksumRule.masked);
    });

    test('find device 50 55 aa tells the rules apart', () {
      final masked = ChecksumCheck.of(padded([0x50, 0x55, 0xAA]));
      final modulo = ChecksumCheck.of(
        padded([0x50, 0x55, 0xAA], ChecksumRule.modulo255),
      );

      expect(masked.match, ChecksumMatch.maskedOnly);
      expect(masked.modulo255, 0x50);
      expect(modulo.match, ChecksumMatch.modulo255Only);
      expect(modulo.masked, 0x4F);
      expect(modulo.satisfiedRule, ChecksumRule.modulo255);
    });

    test('the tahnok R02 capture from realsil-colmi.md is masked only', () {
      final check = ChecksumCheck.of(
        hex('43 23 08 13 14 01 05 b6 18 aa 04 69 03 00 00 83'),
      );

      expect(check.match, ChecksumMatch.maskedOnly);
      expect(check.modulo255, 0x85);
    });

    test('a frame neither rule accepts reports both expected values', () {
      final check = ChecksumCheck.of(
        hex('03 40 00 00 00 00 00 00 00 00 00 00 00 00 00 44'),
      );

      expect(check.match, ChecksumMatch.neither);
      expect(check.satisfiedRule, isNull);
      expect(check.describe(), contains('masked expects 0x43'));
      expect(check.describe(), contains('modulo 255 expects 0x43'));
    });

    test('only a 16 byte frame can be checked', () {
      expect(() => ChecksumCheck.of(const [0x03, 0x03]), throwsArgumentError);
    });
  });

  group('ChecksumTally', () {
    ChecksumTally tally(List<List<int>> frames) {
      final tally = ChecksumTally();
      frames.map(ChecksumCheck.of).forEach(tally.add);
      return tally;
    }

    final both = padded([0x03, 0x50, 0x01]);
    final maskedOnly = padded([0x50, 0x55, 0xAA]);
    final moduloOnly = padded([0x50, 0x55, 0xAA], ChecksumRule.modulo255);
    final neither = hex('03 40 00 00 00 00 00 00 00 00 00 00 00 00 00 44');

    test('frames that never pass 255 keep both rules open', () {
      expect(tally([both, both]).consistentRules, ChecksumRule.values.toSet());
    });

    test('one masked only frame rules out modulo 255', () {
      final t = tally([both, maskedOnly]);
      expect(t.consistentRules, {ChecksumRule.masked});
      expect(t.likelyRule, ChecksumRule.masked);
    });

    test('a modulo 255 majority is the likely rule', () {
      final t = tally([moduloOnly, moduloOnly, both]);
      expect(t.consistentRules, {ChecksumRule.modulo255});
      expect(t.likelyRule, ChecksumRule.modulo255);
    });

    test('a frame neither rule accepts leaves no consistent rule', () {
      final t = tally([both, maskedOnly, neither]);
      expect(t.consistentRules, isEmpty);
      expect(t[ChecksumMatch.neither], 1);
      expect(t.total, 3);
    });

    test('an empty tally proves nothing', () {
      expect(ChecksumTally().consistentRules, isEmpty);
      expect(ChecksumTally().likelyRule, ChecksumRule.masked);
    });

    test('ofEntries counts only 16 byte V1 frames, by direction', () {
      final entries = fixtureEntries('checksum_cases.jsonl');

      final all = ChecksumTally.ofEntries(entries);
      final incoming = ChecksumTally.ofEntries(
        entries,
        direction: TraceDirection.rx,
      );

      expect(all.total, 7);
      expect(all[ChecksumMatch.modulo255Only], 1);
      expect(incoming.total, 5);
      expect(incoming[ChecksumMatch.modulo255Only], 0);
    });

    test('every V1 frame of the heart rate fixture is masked', () {
      final t = ChecksumTally.ofEntries(
        fixtureEntries('heart_rate_sync.jsonl'),
      );

      expect(t.consistentRules, {ChecksumRule.masked});
      expect(t[ChecksumMatch.maskedOnly], 3);
    });
  });

  test('rules parse from their CLI flag', () {
    expect(ChecksumRule.fromFlag('masked'), ChecksumRule.masked);
    expect(ChecksumRule.fromFlag('mod255'), ChecksumRule.modulo255);
    expect(ChecksumRule.fromFlag('crc'), isNull);
    expect(ChecksumRule.modulo255.codec.checksum, isA<Modulo255SumChecksum>());
  });
}
