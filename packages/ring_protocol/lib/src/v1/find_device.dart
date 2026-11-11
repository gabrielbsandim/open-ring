import 'dart:typed_data';

import 'package:ring_protocol/src/parse_result.dart';
import 'package:ring_protocol/src/v1/command.dart';
import 'package:ring_protocol/src/v1/frame.dart';
import 'package:ring_protocol/src/v1/response.dart';

Uint8List findDeviceRequest({V1FrameCodec codec = const V1FrameCodec()}) =>
    codec.encode(V1Command.findDevice, const [0x55, 0xAA]);

ParseResult<V1Frame> parseFindDevice(V1Frame frame) =>
    parseAck(frame, V1Command.findDevice);
