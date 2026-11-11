import 'dart:io';

import 'package:trace_replay/trace_replay.dart';

Future<void> main(List<String> args) async {
  final code = await exitQuietlyOnBrokenPipe(() async {
    final code = await runCli(args, out: stdout, err: stderr);
    await stdout.flush();
    await stderr.flush();
    return code;
  });
  exit(code);
}
