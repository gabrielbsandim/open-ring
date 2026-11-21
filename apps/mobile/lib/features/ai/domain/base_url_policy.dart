import 'package:meta/meta.dart';

enum BaseUrlRejection {
  invalidSyntax,
  unsupportedScheme,
  hasUserInfo,
  hasQueryOrFragment,
  publicCleartext,
  nonPrivateAddress,
}

@immutable
final class NormalizedBaseUrl {
  const new({
    required this.uri,
    required this.asciiHost,
    required this.hasNonAsciiHost,
    required this.port,
  });

  final Uri uri;
  final String asciiHost;
  final bool hasNonAsciiHost;
  final int port;

  String get scheme => uri.scheme;
  String get path => uri.path;
  bool get isCleartext => scheme == 'http';

  String get hostKey {
    final hostPart = asciiHost.contains(':') ? '[$asciiHost]' : asciiHost;
    return '$scheme://$hostPart:$port';
  }

  Uri get chatCompletionsUri =>
      uri.replace(path: '${uri.path}/chat/completions');

  Uri get modelsUri =>
      uri.replace(path: '${uri.path}/models', query: 'limit=1000');

  @override
  bool operator ==(Object other) =>
      other is NormalizedBaseUrl &&
      other.uri == uri &&
      other.asciiHost == asciiHost &&
      other.hasNonAsciiHost == hasNonAsciiHost &&
      other.port == port;

  @override
  int get hashCode => Object.hash(uri, asciiHost, hasNonAsciiHost, port);
}

sealed class BaseUrlResult {
  const new();
}

final class BaseUrlOk extends BaseUrlResult {
  const new(this.url);

  final NormalizedBaseUrl url;
}

final class BaseUrlRejected extends BaseUrlResult {
  const new(this.reason);

  final BaseUrlRejection reason;
}

abstract final class BaseUrlPolicy {
  static final _whitespace = RegExp(r'\s');
  static final _numericOrHexHost = RegExp(
    r'^(?:\d+|0x[0-9a-f]+)$',
    caseSensitive: false,
  );
  static const _privateSuffixes = [
    '.localhost',
    '.local',
    '.lan',
    '.home',
    '.home.arpa',
    '.internal',
  ];

  static BaseUrlResult parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || _whitespace.hasMatch(trimmed)) {
      return const BaseUrlRejected(BaseUrlRejection.invalidSyntax);
    }
    final schemeEnd = trimmed.indexOf('://');
    if (schemeEnd <= 0) {
      return const BaseUrlRejected(BaseUrlRejection.invalidSyntax);
    }
    final rawScheme = trimmed.substring(0, schemeEnd).toLowerCase();
    if (rawScheme != 'http' && rawScheme != 'https') {
      return const BaseUrlRejected(BaseUrlRejection.unsupportedScheme);
    }
    final afterScheme = trimmed.substring(schemeEnd + 3);
    final authority = _sliceAuthority(afterScheme);
    if (authority.isEmpty) {
      return const BaseUrlRejected(BaseUrlRejection.invalidSyntax);
    }
    if (authority.contains('@')) {
      return const BaseUrlRejected(BaseUrlRejection.hasUserInfo);
    }
    if (trimmed.contains('?') || trimmed.contains('#')) {
      return const BaseUrlRejected(BaseUrlRejection.hasQueryOrFragment);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty || !_validPort(uri)) {
      return const BaseUrlRejected(BaseUrlRejection.invalidSyntax);
    }
    final rawHost = _stripPort(authority);
    final hasNonAscii = _detectNonAsciiOrPunycode(rawHost, uri.host);
    final asciiHost = uri.host.toLowerCase();
    final port = uri.port;
    final defaultPort = rawScheme == 'https' ? 443 : 80;
    final cleanPath = _normalizePath(uri.path);
    final normalizedUri = Uri(
      scheme: rawScheme,
      host: asciiHost,
      port: port == defaultPort ? null : port,
      path: cleanPath,
    );
    final normalized = NormalizedBaseUrl(
      uri: normalizedUri,
      asciiHost: asciiHost,
      hasNonAsciiHost: hasNonAscii,
      port: port,
    );
    if (rawScheme == 'http' && !_isAllowedCleartextHost(asciiHost)) {
      return const BaseUrlRejected(BaseUrlRejection.publicCleartext);
    }
    return BaseUrlOk(normalized);
  }

  static bool isPrivateIp(String ip) {
    final clean = _unwrapIp(ip.trim());
    if (clean.isEmpty || clean.contains('%')) return false;
    final ipv4 = _tryParseIpv4(clean);
    if (ipv4 != null) return _isPrivateIpv4Bytes(ipv4);
    final ipv6 = _tryParseIpv6(clean);
    if (ipv6 != null) return _isPrivateIpv6Bytes(ipv6);
    return false;
  }

  static BaseUrlRejection? verifyResolvedAddresses(
    NormalizedBaseUrl url,
    List<String> resolvedIps,
  ) {
    if (!url.isCleartext) return null;
    if (resolvedIps.isEmpty) return BaseUrlRejection.nonPrivateAddress;
    for (final ip in resolvedIps) {
      if (!isPrivateIp(ip)) return BaseUrlRejection.nonPrivateAddress;
    }
    return null;
  }

  static String _sliceAuthority(String afterScheme) {
    for (var i = 0; i < afterScheme.length; i++) {
      final ch = afterScheme[i];
      if (ch == '/' || ch == '?' || ch == '#') {
        return afterScheme.substring(0, i);
      }
    }
    return afterScheme;
  }

  static bool _validPort(Uri uri) =>
      !uri.hasPort || (uri.port >= 1 && uri.port <= 65535);

  static String _stripPort(String authority) {
    if (authority.startsWith('[')) {
      final close = authority.indexOf(']');
      return close < 0 ? authority : authority.substring(1, close);
    }
    final colon = authority.indexOf(':');
    return colon < 0 ? authority : authority.substring(0, colon);
  }

  static bool _detectNonAsciiOrPunycode(String rawHost, String uriHost) {
    for (final unit in rawHost.codeUnits) {
      if (unit > 0x7F) return true;
    }
    if (uriHost.contains('%')) return true;
    for (final label in uriHost.toLowerCase().split('.')) {
      if (label.startsWith('xn--')) return true;
    }
    return false;
  }

  static String _normalizePath(String path) {
    var clean = path.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.toLowerCase().endsWith('/chat/completions')) {
      clean = clean.substring(0, clean.length - '/chat/completions'.length);
    }
    if (clean.toLowerCase().endsWith('/models')) {
      clean = clean.substring(0, clean.length - '/models'.length);
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  static bool _isAllowedCleartextHost(String asciiHost) {
    if (_tryParseIpv4(asciiHost) != null || _tryParseIpv6(asciiHost) != null) {
      return isPrivateIp(asciiHost);
    }
    final clean = asciiHost.endsWith('.')
        ? asciiHost.substring(0, asciiHost.length - 1)
        : asciiHost;
    if (clean.isEmpty || clean.contains('%') || clean.contains(':')) {
      return false;
    }
    if (clean == 'localhost') return true;
    for (final suffix in _privateSuffixes) {
      if (clean.endsWith(suffix)) return true;
    }
    if (!clean.contains('.') && !_numericOrHexHost.hasMatch(clean)) {
      return true;
    }
    return false;
  }

  static String _unwrapIp(String ip) {
    if (ip.startsWith('[') && ip.endsWith(']') && ip.length >= 2) {
      return ip.substring(1, ip.length - 1);
    }
    return ip;
  }

  static List<int>? _tryParseIpv4(String host) {
    try {
      return Uri.parseIPv4Address(host);
    } on FormatException {
      return null;
    }
  }

  static List<int>? _tryParseIpv6(String host) {
    try {
      return Uri.parseIPv6Address(host);
    } on FormatException {
      return null;
    }
  }

  static bool _isPrivateIpv4Bytes(List<int> b) {
    if (b.length != 4) return false;
    if (b[0] == 127 || b[0] == 10) return true;
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
    if (b[0] == 192 && b[1] == 168) return true;
    if (b[0] == 169 && b[1] == 254) return true;
    if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
    return false;
  }

  static bool _isPrivateIpv6Bytes(List<int> b) {
    if (b.length != 16) return false;
    if (_isLoopbackV6(b)) return true;
    if ((b[0] & 0xFE) == 0xFC) return true;
    if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return true;
    if (_isV4Mapped(b)) return _isPrivateIpv4Bytes(b.sublist(12));
    return false;
  }

  static bool _isLoopbackV6(List<int> b) {
    for (var i = 0; i < 15; i++) {
      if (b[i] != 0) return false;
    }
    return b[15] == 1;
  }

  static bool _isV4Mapped(List<int> b) {
    for (var i = 0; i < 10; i++) {
      if (b[i] != 0) return false;
    }
    return b[10] == 0xFF && b[11] == 0xFF;
  }
}
