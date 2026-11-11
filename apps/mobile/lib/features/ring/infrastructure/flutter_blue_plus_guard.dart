import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ring_driver/ring_driver.dart';

Future<T> guardBle<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on FlutterBluePlusException catch (error) {
    throw BleTransportException(
      '${error.function}: ${error.description ?? error.code}',
    );
  } on PlatformException catch (error) {
    throw BleTransportException(error.message ?? error.code);
  } on TimeoutException catch (error) {
    throw BleTransportException(error.message ?? 'timed out');
  }
}
