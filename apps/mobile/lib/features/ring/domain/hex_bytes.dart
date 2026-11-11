abstract final class HexBytes {
  static final _separators = RegExp(r'[\s,:\-]');
  static final _hex = RegExp(r'^[0-9a-fA-F]*$');

  static String encode(List<int> bytes) => bytes.map(_byte).join();

  static String spaced(List<int> bytes) => bytes.map(_byte).join(' ');

  static String id(int value) => '0x${_byte(value).toUpperCase()}';

  static List<int>? tryDecode(String input) {
    final digits = input.replaceAll(_separators, '');
    if (digits.length.isOdd || !_hex.hasMatch(digits)) return null;
    return [
      for (var i = 0; i < digits.length; i += 2)
        int.parse(digits.substring(i, i + 2), radix: 16),
    ];
  }

  static String _byte(int value) =>
      (value & 0xFF).toRadixString(16).padLeft(2, '0');
}
