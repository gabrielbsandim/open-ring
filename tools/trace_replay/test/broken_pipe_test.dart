import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:trace_replay/trace_replay.dart';

const _epipe = OSError('Broken pipe', 32);

void main() {
  group('isBrokenPipe', () {
    test('accepts the errors a closed stdout raises', () {
      expect(isBrokenPipe(const FileSystemException('w', '', _epipe)), isTrue);
      expect(isBrokenPipe(const StdoutException('w', _epipe)), isTrue);
      expect(isBrokenPipe(const SocketException('w', osError: _epipe)), isTrue);
    });

    test('rejects other errors', () {
      const denied = OSError('Permission denied', 13);
      expect(isBrokenPipe(const FileSystemException('w', '', denied)), isFalse);
      expect(isBrokenPipe(const StdoutException('w')), isFalse);
      expect(isBrokenPipe(StateError('w')), isFalse);
    });
  });

  group('exitQuietlyOnBrokenPipe', () {
    test('returns the body exit code', () async {
      expect(await exitQuietlyOnBrokenPipe(() async => ExitCodes.usage), 64);
    });

    test('a broken pipe raised outside the body exits with 0', () async {
      final code = await exitQuietlyOnBrokenPipe(() {
        scheduleMicrotask(
          () => throw const FileSystemException('writeFrom failed', '', _epipe),
        );
        return Completer<int>().future;
      });

      expect(code, ExitCodes.ok);
    });

    test('a broken pipe thrown by the body exits with 0', () async {
      final code = await exitQuietlyOnBrokenPipe(
        () async => throw const StdoutException('flush', _epipe),
      );

      expect(code, ExitCodes.ok);
    });

    test('other errors still fail', () {
      expect(
        exitQuietlyOnBrokenPipe(() async => throw StateError('boom')),
        throwsStateError,
      );
    });
  });

  test(
    'piped into a reader that stops early it exits with 0 and no error',
    () async {
      final dir = await Directory.systemTemp.createTemp('trace_replay');
      addTearDown(() => dir.delete(recursive: true));
      final one = File('test/fixtures/heart_rate_sync.jsonl')
          .readAsStringSync();
      final trace = File('${dir.path}/big.jsonl')
        ..writeAsStringSync(List.filled(400, one).join());

      final process = await Process.start(Platform.resolvedExecutable, [
        'bin/trace_replay.dart',
        'decode',
        trace.path,
      ]);
      final err = process.stderr.transform(utf8.decoder).join();
      final first = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;

      expect(first, startsWith('line 1 '));
      expect(await process.exitCode, 0);
      expect(await err, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
