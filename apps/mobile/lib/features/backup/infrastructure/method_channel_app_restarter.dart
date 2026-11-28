import 'package:flutter/services.dart';
import 'package:open_ring/features/backup/application/restore_coordinator.dart';

final class MethodChannelAppRestarter implements AppRestarter {
  const new([this._channel = const MethodChannel('gbs.openring.app/restart')]);

  final MethodChannel _channel;

  @override
  Future<void> restart() => _channel.invokeMethod<void>('restart');
}
