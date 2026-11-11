abstract final class Hex {
  static final _separators = RegExp(r'[\s,:\-]');
  static final _digits = RegExp(r'^[0-9a-fA-F]*$');

  static String encode(List<int> bytes) => bytes.map(byte).join();

  static String spaced(List<int> bytes) => bytes.map(byte).join(' ');

  static String byte(int value) => value.toRadixString(16).padLeft(2, '0');

  static String word(int value) =>
      '0x${value.toRadixString(16).padLeft(4, '0')}';

  static String id(int value) => '0x${byte(value)}';

  static List<int>? tryDecode(String input) {
    final digits = input.replaceAll(_separators, '');
    if (digits.length.isOdd || !_digits.hasMatch(digits)) return null;
    return [
      for (var i = 0; i < digits.length; i += 2)
        int.parse(digits.substring(i, i + 2), radix: 16),
    ];
  }
}
