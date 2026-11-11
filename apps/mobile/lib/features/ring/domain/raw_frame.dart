import 'package:meta/meta.dart';
import 'package:open_ring/features/ring/domain/hex_bytes.dart';
import 'package:ring_protocol/ring_protocol.dart';

enum RawFrameError { empty, notHex, wrongLength, blockedCommand }

sealed class RawFrameInput {
  const new();
}

@immutable
final class ValidRawFrame extends RawFrameInput {
  new(List<int> bytes) : bytes = List.unmodifiable(bytes);

  final List<int> bytes;
}

@immutable
final class InvalidRawFrame extends RawFrameInput {
  const new(this.error, {this.byteCount = 0});

  final RawFrameError error;
  final int byteCount;
}

abstract final class RawFrame {
  static final Set<int> blockedCommands = {
    V1Command.powerOff.id,
    V1Command.factoryReset.id,
  };

  static RawFrameInput parse(String input) {
    if (input.trim().isEmpty) return const InvalidRawFrame(RawFrameError.empty);
    final bytes = HexBytes.tryDecode(input);
    if (bytes == null) return const InvalidRawFrame(RawFrameError.notHex);
    if (bytes.length != V1Frame.length) {
      return InvalidRawFrame(
        RawFrameError.wrongLength,
        byteCount: bytes.length,
      );
    }
    if (blockedCommands.contains(bytes.first)) {
      return const InvalidRawFrame(RawFrameError.blockedCommand);
    }
    return ValidRawFrame(bytes);
  }
}
