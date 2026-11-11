import 'package:ring_protocol/ring_protocol.dart';

enum ChecksumRule {
  masked(MaskedSumChecksum()),
  modulo255(Modulo255SumChecksum());

  new(this.strategy);

  final ChecksumStrategy strategy;

  V1FrameCodec get codec => V1FrameCodec(checksum: strategy);
}
