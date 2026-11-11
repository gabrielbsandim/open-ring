import 'dart:isolate';
import 'dart:ui';

const backgroundSyncPortName = 'open_ring/background_sync_finished';

// The name server spans every engine of the process, unlike drift's stream
// updates; only a null message is sent so it can cross isolate groups.
void announceBackgroundSyncFinished() =>
    IsolateNameServer.lookupPortByName(backgroundSyncPortName)?.send(null);

Stream<void> backgroundSyncFinishedEvents() {
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(backgroundSyncPortName);
  IsolateNameServer.registerPortWithName(port.sendPort, backgroundSyncPortName);
  return port.map<void>((_) {}).asBroadcastStream();
}
