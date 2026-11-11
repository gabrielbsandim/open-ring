import 'dart:async';
import 'dart:io';

import 'package:trace_replay/src/cli.dart';

// EPIPE on Linux and macOS, ERROR_BROKEN_PIPE and ERROR_NO_DATA on Windows.
const _brokenPipeCodes = {32, 109, 232};

bool isBrokenPipe(Object error) {
  final osError = switch (error) {
    FileSystemException(:final osError) => osError,
    StdoutException(:final osError) => osError,
    SocketException(:final osError) => osError,
    _ => null,
  };
  if (osError == null) return false;
  return _brokenPipeCodes.contains(osError.errorCode);
}

Future<int> exitQuietlyOnBrokenPipe(Future<int> Function() body) {
  final result = Completer<int>();
  runZonedGuarded(() => unawaited(_complete(body, result)), (error, stack) {
    if (result.isCompleted) return;
    if (isBrokenPipe(error)) {
      result.complete(ExitCodes.ok);
      return;
    }
    result.completeError(error, stack);
  });
  return result.future;
}

Future<void> _complete(
  Future<int> Function() body,
  Completer<int> result,
) async {
  final code = await body();
  if (!result.isCompleted) result.complete(code);
}
