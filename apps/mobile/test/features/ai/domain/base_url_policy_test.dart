import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_provider_preset.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';

NormalizedBaseUrl _expectOk(String raw) {
  final result = BaseUrlPolicy.parse(raw);
  expect(result, isA<BaseUrlOk>(), reason: raw);
  return (result as BaseUrlOk).url;
}

void _expectRejected(String raw, BaseUrlRejection expected) {
  final result = BaseUrlPolicy.parse(raw);
  expect(result, isA<BaseUrlRejected>(), reason: raw);
  expect((result as BaseUrlRejected).reason, expected, reason: raw);
}

void main() {
  group('BaseUrlPolicy.parse normalization', () {
    test('trims whitespace, strips trailing slash and known suffixes, never adds /v1', () {
      final plain = _expectOk('  https://api.openai.com/v1/  ');
      expect(plain.uri.toString(), 'https://api.openai.com/v1');
      expect(plain.hostKey, 'https://api.openai.com:443');
      expect(
        plain.chatCompletionsUri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        plain.modelsUri.toString(),
        'https://api.openai.com/v1/models?limit=1000',
      );

      final fromChat = _expectOk('https://api.openai.com/v1/chat/completions/');
      expect(fromChat, plain);

      final fromModels = _expectOk('https://api.openai.com/v1/MODELS');
      expect(fromModels, plain);

      final withDefaultPort = _expectOk('https://api.openai.com:443/v1');
      expect(withDefaultPort, plain);
      expect(identical(withDefaultPort, plain), isFalse);
      expect(withDefaultPort.hashCode, plain.hashCode);
      expect(withDefaultPort.scheme, 'https');

      final httpDefaultPort = _expectOk('http://localhost:80/v1');
      expect(httpDefaultPort.hostKey, 'http://localhost:80');
      expect(httpDefaultPort.uri.toString(), 'http://localhost/v1');

      final encodedPath = _expectOk('https://example.com/my%20api/v1');
      expect(encodedPath.path, '/my%20api/v1');
      expect(
        encodedPath.chatCompletionsUri.path,
        '/my%20api/v1/chat/completions',
      );
      expect(encodedPath.modelsUri.path, '/my%20api/v1/models');

      final nonAsciiPath = _expectOk('https://example.com/café/v1');
      expect(nonAsciiPath.path, '/caf%C3%A9/v1');
      expect(
        nonAsciiPath.chatCompletionsUri.path,
        '/caf%C3%A9/v1/chat/completions',
      );

      final bare = _expectOk('https://custom.example');
      expect(bare.path, '');
      expect(
        bare.chatCompletionsUri.toString(),
        'https://custom.example/chat/completions',
      );
      expect(
        bare.modelsUri.toString(),
        'https://custom.example/models?limit=1000',
      );
    });

    test('supports custom ports and IPv6 hostKey formatting', () {
      final ipv6 = _expectOk('http://[::1]:11434/v1');
      expect(ipv6.isCleartext, isTrue);
      expect(ipv6.asciiHost, '::1');
      expect(ipv6.port, 11434);
      expect(ipv6.hostKey, 'http://[::1]:11434');
      expect(
        ipv6.chatCompletionsUri.toString(),
        'http://[::1]:11434/v1/chat/completions',
      );
    });

    test('covers NormalizedBaseUrl value equality across all 4 fields', () {
      final a1 = _expectOk('https://api.openai.com/v1');
      final a2 = _expectOk('https://api.openai.com/v1');
      expect(identical(a1, a2), isFalse);
      expect(a1, a2);
      expect(a1.hashCode, a2.hashCode);
      expect(a1, isNot(_expectOk('https://api.openai.com/v2')));
      expect(
        a1,
        isNot(
          NormalizedBaseUrl(
            uri: a1.uri,
            asciiHost: 'other.openai.com',
            hasNonAsciiHost: a1.hasNonAsciiHost,
            port: a1.port,
          ),
        ),
      );
      expect(
        a1,
        isNot(
          NormalizedBaseUrl(
            uri: a1.uri,
            asciiHost: a1.asciiHost,
            hasNonAsciiHost: !a1.hasNonAsciiHost,
            port: a1.port,
          ),
        ),
      );
      expect(
        a1,
        isNot(
          NormalizedBaseUrl(
            uri: a1.uri,
            asciiHost: a1.asciiHost,
            hasNonAsciiHost: a1.hasNonAsciiHost,
            port: 8443,
          ),
        ),
      );
    });

    test('flags non-ASCII and punycode hosts', () {
      final nonAscii = _expectOk('https://café.example/v1');
      expect(nonAscii.hasNonAsciiHost, isTrue);

      final punycode = _expectOk('https://xn--caf-dma.example/v1');
      expect(punycode.hasNonAsciiHost, isTrue);

      final ascii = _expectOk('https://openrouter.ai/api/v1');
      expect(ascii.hasNonAsciiHost, isFalse);
    });
  });

  group('BaseUrlPolicy.parse rejections', () {
    test('rejects invalid syntax, schemes, userinfo, query, and fragment', () {
      _expectRejected('', BaseUrlRejection.invalidSyntax);
      _expectRejected('   ', BaseUrlRejection.invalidSyntax);
      _expectRejected(
        'https://api.openai.com/v 1',
        BaseUrlRejection.invalidSyntax,
      );
      _expectRejected(
        'https://api.openai.com/\tv1',
        BaseUrlRejection.invalidSyntax,
      );
      _expectRejected('api.openai.com/v1', BaseUrlRejection.invalidSyntax);
      _expectRejected('https://:443/v1', BaseUrlRejection.invalidSyntax);
      _expectRejected(
        'https://api.openai.com:0/v1',
        BaseUrlRejection.invalidSyntax,
      );
      _expectRejected(
        'https://api.openai.com:99999/v1',
        BaseUrlRejection.invalidSyntax,
      );
      _expectRejected(
        'ftp://api.openai.com/v1',
        BaseUrlRejection.unsupportedScheme,
      );
      _expectRejected('file:///tmp/model', BaseUrlRejection.unsupportedScheme);
      _expectRejected(
        'https://api.openai.com@evil.example/v1',
        BaseUrlRejection.hasUserInfo,
      );
      _expectRejected('https://@evil.example/v1', BaseUrlRejection.hasUserInfo);
      _expectRejected(
        'https://api.openai.com/v1?key=1',
        BaseUrlRejection.hasQueryOrFragment,
      );
      _expectRejected(
        'https://api.openai.com/v1?',
        BaseUrlRejection.hasQueryOrFragment,
      );
      _expectRejected(
        'https://api.openai.com/v1#frag',
        BaseUrlRejection.hasQueryOrFragment,
      );
      _expectRejected(
        'https://api.openai.com/v1#',
        BaseUrlRejection.hasQueryOrFragment,
      );
      _expectRejected('http://.local', BaseUrlRejection.invalidSyntax);
      _expectRejected('https://..', BaseUrlRejection.invalidSyntax);
      _expectRejected('http://!', BaseUrlRejection.invalidSyntax);
      _expectRejected(
        'https://-bad.example/v1',
        BaseUrlRejection.invalidSyntax,
      );
      _expectRejected(
        'https://bad-.example/v1',
        BaseUrlRejection.invalidSyntax,
      );
      _expectRejected('http://[not-ip]/v1', BaseUrlRejection.invalidSyntax);
      _expectRejected(
        'http://[fe80::1%25eth0]/v1',
        BaseUrlRejection.invalidSyntax,
      );
    });

    test('allows private cleartext http and rejects public cleartext http', () {
      for (final allowed in [
        'http://localhost:11434/v1',
        'http://macmini:11434/v1',
        'http://ollama.local:11434/v1',
        'http://nas.home.arpa/v1',
        'http://127.0.0.1:11434/v1',
        'http://10.0.0.5:11434/v1',
        'http://172.16.0.1/v1',
        'http://172.31.255.254/v1',
        'http://192.168.1.10:11434/v1',
        'http://169.254.1.2/v1',
        'http://100.64.0.1:11434/v1',
        'http://100.127.255.254/v1',
        'http://[::1]:11434/v1',
        'http://[fc00::1]/v1',
        'http://[fd12::1]/v1',
        'http://[fe80::1]/v1',
        'http://[::ffff:192.168.1.10]/v1',
      ]) {
        expect(_expectOk(allowed).isCleartext, isTrue, reason: allowed);
      }

      for (final blocked in [
        'http://api.openai.com/v1',
        'http://8.8.8.8/v1',
        'http://0.0.0.0:11434/v1',
        'http://2130706433/v1',
        'http://0x7f000001/v1',
        'http://[::]/v1',
        'http://[::ffff:8.8.8.8]/v1',
      ]) {
        _expectRejected(blocked, BaseUrlRejection.publicCleartext);
      }
    });
  });

  group('BaseUrlPolicy.isPrivateIp boundaries', () {
    test('checks CIDR boundaries accurately', () {
      for (final priv in [
        '127.0.0.1',
        '10.0.0.0',
        '172.16.0.0',
        '172.31.255.255',
        '192.168.0.1',
        '169.254.10.20',
        '100.64.0.1',
        '100.127.255.255',
        '::1',
        '[::1]',
        'fc00::1',
        'fdff::1',
        'fe80::1',
        'febf::1',
        '::ffff:10.0.0.1',
      ]) {
        expect(BaseUrlPolicy.isPrivateIp(priv), isTrue, reason: priv);
      }

      for (final pub in [
        '',
        '0.0.0.0',
        '8.8.8.8',
        '172.15.255.255',
        '172.32.0.0',
        '100.63.255.255',
        '100.128.0.0',
        '192.169.0.1',
        '169.253.0.1',
        '::',
        'fe7f::1',
        'fec0::1',
        'fbff::1',
        'fe00::1',
        '::ffff:8.8.8.8',
        'fe80::1%eth0',
        'not-an-ip',
      ]) {
        expect(BaseUrlPolicy.isPrivateIp(pub), isFalse, reason: pub);
      }
    });
  });

  group('BaseUrlPolicy.verifyResolvedAddresses', () {
    test(
      'allows https unconditionally and enforces all-private IPs on http',
      () {
        final httpsUrl = _expectOk('https://api.openai.com/v1');
        expect(
          BaseUrlPolicy.verifyResolvedAddresses(httpsUrl, const []),
          isNull,
        );
        expect(
          BaseUrlPolicy.verifyResolvedAddresses(httpsUrl, const ['8.8.8.8']),
          isNull,
        );

        final httpUrl = _expectOk('http://ollama.local:11434/v1');
        expect(
          BaseUrlPolicy.verifyResolvedAddresses(httpUrl, const []),
          BaseUrlRejection.nonPrivateAddress,
        );
        expect(
          BaseUrlPolicy.verifyResolvedAddresses(httpUrl, const ['8.8.8.8']),
          BaseUrlRejection.nonPrivateAddress,
        );
        expect(
          BaseUrlPolicy.verifyResolvedAddresses(httpUrl, const [
            '192.168.1.10',
            '93.184.216.34',
          ]),
          BaseUrlRejection.nonPrivateAddress,
        );
        expect(
          BaseUrlPolicy.verifyResolvedAddresses(httpUrl, const [
            '192.168.1.10',
            'fd00::1',
          ]),
          isNull,
        );
        expect(
          BaseUrlPolicy.verifyResolvedAddresses(httpUrl, const [
            '192.168.1.10',
            'fe80::1%wlan0',
          ]),
          isNull,
        );
        expect(
          BaseUrlPolicy.verifyResolvedAddresses(httpUrl, const [
            'fe80::215:5dff:fefc:a8e3%eth0.2',
          ]),
          isNull,
        );
        for (final badScoped in [
          const ['fe80::1%'],
          const ['fe80::1%eth0%2'],
          const ['fe80::1%eth 0'],
          const ['192.168.1.10%eth0'],
          const ['fc00::1%eth0'],
          const ['2001:db8::1%eth0'],
          const ['fe80::1%wlan0', '8.8.8.8'],
        ]) {
          expect(
            BaseUrlPolicy.verifyResolvedAddresses(httpUrl, badScoped),
            BaseUrlRejection.nonPrivateAddress,
            reason: badScoped.join(','),
          );
        }
      },
    );
  });

  group('AiProviderPreset', () {
    test(
      'defines URL-only presets without model IDs and valid HTTPS defaults',
      () {
        expect(AiProviderPreset.values, hasLength(8));
        const remote = {
          AiProviderPreset.openAi,
          AiProviderPreset.openRouter,
          AiProviderPreset.groq,
          AiProviderPreset.gemini,
          AiProviderPreset.anthropic,
        };
        const local = {AiProviderPreset.ollama, AiProviderPreset.lmStudio};
        for (final preset in AiProviderPreset.values) {
          if (remote.contains(preset)) {
            expect(preset.baseUrl, isNotEmpty, reason: preset.name);
            expect(preset.placeholderUrl, isEmpty, reason: preset.name);
            expect(_expectOk(preset.baseUrl).isCleartext, isFalse);
            expect(preset.isLocal, isFalse);
            continue;
          }
          expect(preset.baseUrl, isEmpty, reason: preset.name);
          if (local.contains(preset)) {
            expect(preset.placeholderUrl, isNotEmpty, reason: preset.name);
            expect(_expectOk(preset.placeholderUrl).isCleartext, isTrue);
            expect(preset.isLocal, isTrue);
            continue;
          }
          expect(preset.placeholderUrl, isEmpty, reason: preset.name);
        }
        expect(AiProviderPreset.ollama.defaultTimeoutSeconds, 600);
        expect(AiProviderPreset.lmStudio.defaultCompactContext, isTrue);
        expect(AiProviderPreset.openAi.defaultTimeoutSeconds, 180);
        expect(AiProviderPreset.openAi.defaultCompactContext, isFalse);
        expect(AiProviderPreset.openAi.keyRequired, isTrue);
        expect(AiProviderPreset.ollama.keyRequired, isFalse);
        expect(AiProviderPreset.custom.isLocal, isFalse);
        expect(AiProviderPreset.custom.defaultTimeoutSeconds, 180);
        expect(AiProviderPreset.custom.defaultCompactContext, isFalse);
        expect(AiProviderPreset.custom.keyRequired, isFalse);
      },
    );
  });
}
