import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/infrastructure/background_sync_signal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(
    () => IsolateNameServer.removePortNameMapping(backgroundSyncPortName),
  );

  test('announcing with nobody listening does nothing', () {
    IsolateNameServer.removePortNameMapping(backgroundSyncPortName);

    expect(announceBackgroundSyncFinished, returnsNormally);
  });

  test('announcing reaches the registered port', () async {
    final port = ReceivePort();
    addTearDown(port.close);
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      backgroundSyncPortName,
    );

    announceBackgroundSyncFinished();

    await expectLater(
      port.first.timeout(const Duration(seconds: 5)),
      completion(isNull),
    );
  });

  test('the event stream takes over a stale registration', () async {
    final stale = ReceivePort();
    addTearDown(stale.close);
    IsolateNameServer.registerPortWithName(
      stale.sendPort,
      backgroundSyncPortName,
    );

    final events = backgroundSyncFinishedEvents();
    final received = events.first.timeout(const Duration(seconds: 5));
    announceBackgroundSyncFinished();

    await expectLater(received, completes);
  });
}
