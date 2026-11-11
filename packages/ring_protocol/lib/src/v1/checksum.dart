// An R09 reply settled the rule as the masked sum; modulo 255 stays for the
// protocol lab and for other models (docs/protocols/realsil-colmi.md).
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
