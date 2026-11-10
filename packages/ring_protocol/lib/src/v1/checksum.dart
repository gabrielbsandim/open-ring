// The sources disagree on the rule (docs/protocols/realsil-colmi.md), so it
// stays pluggable until a frame captured from the ring settles it.
abstract interface class ChecksumStrategy {
  int compute(List<int> bytes);
}

final class MaskedSumChecksum implements ChecksumStrategy {
  const new();

  @override
  int compute(List<int> bytes) =>
      bytes.fold<int>(0, (sum, b) => sum + b) & 0xFF;
}

final class Modulo255SumChecksum implements ChecksumStrategy {
  const new();

  @override
  int compute(List<int> bytes) => bytes.fold<int>(0, (sum, b) => sum + b) % 255;
}
