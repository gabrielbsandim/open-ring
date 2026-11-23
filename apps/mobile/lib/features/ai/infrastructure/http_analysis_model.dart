import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';

const String openRingUserAgent = 'OpenRing';
const String probeUserMessage =
    'Reply with this JSON and nothing else: {"ok":true}';
const int _maxLadderAttempts = 4;
const Duration _connectTimeout = Duration(seconds: 10);
const Duration _modelsTimeout = Duration(seconds: 10);

typedef AddressLookup = Future<List<String>> Function(String host);

/// Builds the transport for one run. [pinnedIp] is set for cleartext URLs only.
typedef AnalysisClientFactory = http.Client Function(
  NormalizedBaseUrl url,
  String? pinnedIp,
);

Future<List<String>> systemAddressLookup(String host) async => [
  for (final address in await InternetAddress.lookup(host)) address.address,
];

http.Client pinnedIoClient(NormalizedBaseUrl url, String? pinnedIp) {
  final inner = HttpClient()
    ..connectionTimeout = _connectTimeout
    ..userAgent = openRingUserAgent
    ..findProxy = ((_) => 'DIRECT')
    ..badCertificateCallback = ((_, _, _) => false);
  if (pinnedIp == null) return IOClient(inner);
  final address = InternetAddress(pinnedIp);
  inner.connectionFactory = (_, _, _) => Socket.startConnect(address, url.port);
  return IOClient(inner);
}

final class HttpAnalysisModel implements AnalysisModel {
  new({
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.local = false,
    this.requestTimeout = const Duration(seconds: 180),
    this.profileStore,
    AddressLookup? lookup,
    AnalysisClientFactory? clientFactory,
  }) : _lookup = lookup ?? systemAddressLookup,
       _clientFactory = clientFactory ?? pinnedIoClient;

  static const AnalysisRequest probeRequest = AnalysisRequest(
    systemPrompt: 'You are a connection test. Answer with JSON only.',
    userContent: AiTextContent(probeUserMessage),
    maxOutputTokens: 512,
    jsonSchema: {
      'type': 'object',
      'properties': {
        'ok': {'type': 'boolean'},
      },
      'required': ['ok'],
      'additionalProperties': false,
    },
  );

  final NormalizedBaseUrl baseUrl;
  final String model;
  final String? apiKey;
  final bool local;
  final Duration requestTimeout;
  final AiConfigStore? profileStore;
  final AddressLookup _lookup;
  final AnalysisClientFactory _clientFactory;

  Duration get _firstByte => Duration(seconds: local ? 180 : 60);
  Duration get _idle => Duration(seconds: local ? 120 : 45);
  Duration get _probeTimeout => Duration(seconds: local ? 180 : 60);

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) async* {
    final run = await _open(requestTimeout, cancel: cancel);
    try {
      final (response, profile) = await _sendChat(run, request);
      if (profile != request.profile) await _storeProfile(profile);
      yield* _decode(run, response);
    } finally {
      run.close();
    }
  }

  @override
  Future<List<String>> listModels() async {
    final run = await _open(_modelsTimeout);
    try {
      final response = await _send(run, 'GET', baseUrl.modelsUri);
      final text = await _readText(run, response);
      if (!_isSuccess(response)) throw _classify(response, text);
      return OpenAiWireCodec.parseModelsList(text);
    } finally {
      run.close();
    }
  }

  @override
  Future<ConnectionProbe> probe() async {
    final models = await _probeModels();
    final stopwatch = Stopwatch()..start();
    final run = await _open(_probeTimeout);
    try {
      final (response, profile) = await _sendChat(run, probeRequest);
      final last = await _decode(run, response).last;
      if (last is! AnalysisCompleted) {
        throw const AnalysisFailure(kind: AnalysisFailureKind.unreadable);
      }
      await _storeProfile(profile);
      return ConnectionProbe(
        profile: profile,
        latency: stopwatch.elapsed,
        models: models,
        usage: last.usage,
      );
    } finally {
      run.close();
    }
  }

  Future<List<String>?> _probeModels() async {
    try {
      return await listModels();
    } on AnalysisFailure catch (failure) {
      if (failure.statusCode == 404 || failure.statusCode == 405) return null;
      rethrow;
    }
  }

  Future<void> _storeProfile(AiCapabilityProfile profile) =>
      profileStore?.writeCapabilityProfile(baseUrl.hostKey, model, profile) ??
      Future.value();

  Future<_Run> _open(Duration total, {Future<void>? cancel}) async {
    final pinnedIp = await _pinnedAddress();
    return _Run(
      _clientFactory(baseUrl, pinnedIp),
      total: total,
      cancel: cancel,
      apiKey: apiKey,
    );
  }

  Future<String?> _pinnedAddress() async {
    if (!baseUrl.isCleartext) return null;
    final List<String> ips;
    try {
      ips = await _lookup(baseUrl.asciiHost);
    } on Object catch (error) {
      throw AnalysisFailure(
        kind: AnalysisFailureKind.unreachable,
        detail: scrubApiKey('$error', apiKey),
      );
    }
    if (BaseUrlPolicy.verifyResolvedAddresses(baseUrl, ips) != null) {
      throw const AnalysisFailure(kind: AnalysisFailureKind.cleartextBlocked);
    }
    return ips.first;
  }

  Future<(http.StreamedResponse, AiCapabilityProfile)> _sendChat(
    _Run run,
    AnalysisRequest request,
  ) async {
    var profile = request.profile;
    for (var attempt = 1; ; attempt++) {
      final body = OpenAiWireCodec.buildChatBody(
        model: model,
        systemPrompt: request.systemPrompt,
        userContent: request.userContent,
        maxOutputTokens: request.maxOutputTokens,
        profile: profile,
        jsonSchema: request.jsonSchema,
        reasoningEffort: request.reasoningEffort,
      );
      final response = await _send(
        run,
        'POST',
        baseUrl.chatCompletionsUri,
        body: body,
      );
      if (_isSuccess(response)) return (response, profile);
      final failure = _classify(response, await _readText(run, response));
      final next = _stepDown(failure, profile, attempt);
      if (next == null) throw failure;
      profile = next;
    }
  }

  static AiCapabilityProfile? _stepDown(
    AnalysisFailure failure,
    AiCapabilityProfile profile,
    int attempt,
  ) {
    if (attempt >= _maxLadderAttempts) return null;
    if (failure.statusCode != 400) return null;
    if (failure.kind != AnalysisFailureKind.badRequest) return null;
    return profile.nextOnBadRequest(failure.detail);
  }

  Future<http.StreamedResponse> _send(
    _Run run,
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: run.abortTrigger,
    )..followRedirects = false;
    request.headers['user-agent'] = openRingUserAgent;
    request.headers['accept'] = 'application/json, text/event-stream';
    final key = apiKey?.trim() ?? '';
    if (key.isNotEmpty) request.headers['authorization'] = 'Bearer $key';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    run.arm(TimeoutStage.firstByte, _firstByte);
    try {
      return await run.guard(run.client.send(request));
    } on Object catch (error) {
      throw run.translate(error);
    }
  }

  Stream<AnalysisEvent> _decode(_Run run, http.StreamedResponse response) {
    final bytes = run.watch(response.stream, _idle);
    final type = response.headers['content-type'] ?? '';
    if (type.contains('event-stream')) {
      return OpenAiWireCodec.parseSseStream(bytes, apiKey: apiKey);
    }
    return Stream.fromFuture(
      _collect(
        bytes,
      ).then((text) => OpenAiWireCodec.parseJsonResponse(text, apiKey: apiKey)),
    );
  }

  Future<String> _readText(_Run run, http.StreamedResponse response) =>
      _collect(run.watch(response.stream, _idle));

  static Future<String> _collect(Stream<List<int>> bytes) async =>
      utf8.decode(await http.ByteStream(bytes).toBytes(), allowMalformed: true);

  static bool _isSuccess(http.StreamedResponse response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  AnalysisFailure _classify(http.StreamedResponse response, String text) =>
      OpenAiWireCodec.classifyHttpError(
        statusCode: response.statusCode,
        body: text,
        headers: response.headers,
        apiKey: apiKey,
      );
}

/// One request lifecycle: owns the client, the stage timers and the abort.
final class _Run {
  new(
    this.client, {
    required Duration total,
    required this.apiKey,
    Future<void>? cancel,
  }) {
    _total = Timer(total, () => fail(_timeout(TimeoutStage.total, total)));
    if (cancel == null) return;
    unawaited(
      cancel.then(
        (_) => fail(_cancelled),
        onError: (Object _) => fail(_cancelled),
      ),
    );
  }

  static const _cancelled = AnalysisFailure(
    kind: AnalysisFailureKind.cancelled,
  );

  final http.Client client;
  final String? apiKey;
  final Completer<void> _abort = Completer<void>();
  late final Timer _total;
  Timer? _stage;
  AnalysisFailure? _failure;
  bool _closed = false;

  Future<void> get abortTrigger => _abort.future;

  void fail(AnalysisFailure failure) {
    if (_closed || _abort.isCompleted) return;
    _failure = failure;
    _abort.complete();
    close();
  }

  void arm(TimeoutStage stage, Duration after) {
    _stage?.cancel();
    _stage = Timer(after, () => fail(_timeout(stage, after)));
  }

  void close() {
    _closed = true;
    _total.cancel();
    _stage?.cancel();
    client.close();
  }

  Future<T> guard<T>(Future<T> work) =>
      Future.any([work, _abort.future.then<T>((_) => throw _failure!)]);

  /// Races the body against the timers and the cancel, and caps its size,
  /// because a mock or a hung socket ignores the abort trigger.
  Stream<List<int>> watch(Stream<List<int>> source, Duration idle) {
    final out = StreamController<List<int>>();
    var received = 0;
    late final StreamSubscription<List<int>> sub;
    void stop(Object error) {
      if (out.isClosed) return;
      out.addError(error);
      unawaited(out.close());
      unawaited(sub.cancel());
    }

    sub = source.listen(
      (chunk) {
        received += chunk.length;
        if (received > aiMaxResponseBytes) {
          stop(const AnalysisFailure(kind: AnalysisFailureKind.unreadable));
          return;
        }
        arm(TimeoutStage.idle, idle);
        out.add(chunk);
      },
      onError: (Object error) => stop(translate(error)),
      onDone: () {
        _stage?.cancel();
        if (!out.isClosed) unawaited(out.close());
      },
    );
    out.onCancel = sub.cancel;
    unawaited(_abort.future.then((_) => stop(_failure!)));
    return out.stream;
  }

  AnalysisFailure translate(Object error) =>
      _failure ??
      switch (error) {
        AnalysisFailure() => error,
        http.RequestAbortedException() => _cancelled,
        TlsException() => _failed(AnalysisFailureKind.tls, error),
        TimeoutException() => _timeout(TimeoutStage.connect, _connectTimeout),
        _ => _failed(AnalysisFailureKind.unreachable, error),
      };

  AnalysisFailure _failed(AnalysisFailureKind kind, Object error) =>
      AnalysisFailure(kind: kind, detail: scrubApiKey('$error', apiKey));

  static AnalysisFailure _timeout(TimeoutStage stage, Duration after) =>
      AnalysisFailure(
        kind: AnalysisFailureKind.timeout,
        timeoutStage: stage,
        detail: '${after.inSeconds}',
      );
}
