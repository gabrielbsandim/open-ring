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
  static final _hostLabel = RegExp(
    r'^[a-z0-9\u0080-\uffff](?:[a-z0-9\u0080-\uffff-]{0,61}[a-z0-9\u0080-\uffff])?$',
    caseSensitive: false,
  );
  static final _numericOrHexHost = RegExp(
    r'^(?:\d+|0x[0-9a-f]+)$',
    caseSensitive: false,
  );
  static final _zoneId = RegExp(r'^[A-Za-z0-9._-]+$');
  static final _trailingSlashes = RegExp(r'/+$');
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
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      return const BaseUrlRejected(BaseUrlRejection.invalidSyntax);
    }
    final rawHost = _stripPort(authority);
    final asciiHost = uri.host.toLowerCase();
    if (!_validHost(rawHost, asciiHost, bracketed: authority.startsWith('['))) {
      return const BaseUrlRejected(BaseUrlRejection.invalidSyntax);
    }
    final hasNonAscii = _detectNonAsciiOrPunycode(rawHost, uri.host);
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
    final ipv4 = _parseIp(clean, Uri.parseIPv4Address);
    if (ipv4 != null) return _isPrivateIpv4Bytes(ipv4);
    final ipv6 = _parseIp(clean, Uri.parseIPv6Address);
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
      if (!_isResolvedPrivateIp(ip)) return BaseUrlRejection.nonPrivateAddress;
    }
    return null;
  }

  static bool _isResolvedPrivateIp(String ip) {
    final trimmed = ip.trim();
    final pct = trimmed.indexOf('%');
    if (pct < 0) return isPrivateIp(trimmed);
    if (pct == 0 || !_zoneId.hasMatch(trimmed.substring(pct + 1))) {
      return false;
    }
    final ipv6 = _parseIp(trimmed.substring(0, pct), Uri.parseIPv6Address);
    return ipv6 != null && _isLinkLocalV6(ipv6);
  }

  static String _sliceAuthority(String after) {
    final end = after.indexOf(RegExp('[/?#]'));
    return end < 0 ? after : after.substring(0, end);
  }

  static bool _validHost(
    String rawHost,
    String asciiHost, {
    required bool bracketed,
  }) {
    if (bracketed) return _parseIp(asciiHost, Uri.parseIPv6Address) != null;
    if (_parseIp(asciiHost, Uri.parseIPv4Address) != null) return true;
    final clean = _stripDot(rawHost);
    if (clean.isEmpty || clean.contains(':')) return false;
    return clean.split('.').every(_hostLabel.hasMatch);
  }

  static String _stripPort(String authority) {
    if (authority.startsWith('[')) {
      final close = authority.indexOf(']');
      return close < 0 ? authority : authority.substring(1, close);
    }
    final colon = authority.indexOf(':');
    return colon < 0 ? authority : authority.substring(0, colon);
  }

  static bool _detectNonAsciiOrPunycode(String rawHost, String uriHost) =>
      rawHost.codeUnits.any((u) => u > 0x7F) ||
      uriHost.contains('%') ||
      uriHost.toLowerCase().split('.').any((l) => l.startsWith('xn--'));

  static String _normalizePath(String path) {
    var clean = path.trim().replaceAll(_trailingSlashes, '');
    if (clean.toLowerCase().endsWith('/chat/completions')) {
      clean = clean.substring(0, clean.length - '/chat/completions'.length);
    }
    if (clean.toLowerCase().endsWith('/models')) {
      clean = clean.substring(0, clean.length - '/models'.length);
    }
    return clean.replaceAll(_trailingSlashes, '');
  }

  static bool _isAllowedCleartextHost(String asciiHost) {
    if (_parseIp(asciiHost, Uri.parseIPv4Address) != null ||
        _parseIp(asciiHost, Uri.parseIPv6Address) != null) {
      return isPrivateIp(asciiHost);
    }
    final clean = _stripDot(asciiHost);
    if (clean.isEmpty || clean.contains('%') || clean.contains(':')) {
      return false;
    }
    if (clean == 'localhost' || _privateSuffixes.any(clean.endsWith)) {
      return true;
    }
    return !clean.contains('.') && !_numericOrHexHost.hasMatch(clean);
  }

  static String _stripDot(String host) =>
      host.endsWith('.') ? host.substring(0, host.length - 1) : host;

  static String _unwrapIp(String ip) {
    if (ip.startsWith('[') && ip.endsWith(']') && ip.length >= 2) {
      return ip.substring(1, ip.length - 1);
    }
    return ip;
  }

  static List<int>? _parseIp(String host, List<int> Function(String) parser) {
    try {
      return parser(host);
    } on FormatException {
      return null;
    }
  }

  static bool _isPrivateIpv4Bytes(List<int> b) =>
      b.length == 4 &&
      (b[0] == 127 ||
          b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127));

  static bool _isPrivateIpv6Bytes(List<int> b) =>
      b.length == 16 &&
      (_isLoopbackV6(b) ||
          (b[0] & 0xFE) == 0xFC ||
          _isLinkLocalV6(b) ||
          (_isV4Mapped(b) && _isPrivateIpv4Bytes(b.sublist(12))));

  static bool _isLinkLocalV6(List<int> b) =>
      b[0] == 0xFE && (b[1] & 0xC0) == 0x80;

  static bool _isLoopbackV6(List<int> b) =>
      b.sublist(0, 15).every((v) => v == 0) && b[15] == 1;

  static bool _isV4Mapped(List<int> b) =>
      b.sublist(0, 10).every((v) => v == 0) && b[10] == 0xFF && b[11] == 0xFF;
}
