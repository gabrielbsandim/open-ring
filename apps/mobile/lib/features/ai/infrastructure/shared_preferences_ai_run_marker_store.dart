import 'dart:convert';

import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesAiRunMarkerStore implements AiRunMarkerStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'ai_run_marker';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<AiReport?> read() async {
    final raw = await _store.getString(key);
    if (raw == null) return null;
    try {
      final [at, offset, ...rest] = jsonDecode(raw) as List<Object?>;
      final [kind, schema, sha, detail, prompt, host, model] = rest
          .cast<String>();
      return AiReport(
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
          at! as int,
          isUtc: true,
        ),
        offsetMin: offset! as int,
        kind: kind,
        contextSchema: schema,
        contextSha256: sha,
        detailLevel: detail,
        promptVersion: prompt,
        providerHost: host,
        model: model,
        status: AiReportStatus.failed,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(AiReport d) => _store.setString(
    key,
    jsonEncode([
      d.createdAtUtc.millisecondsSinceEpoch,
      d.offsetMin,
      d.kind,
      d.contextSchema,
      d.contextSha256,
      d.detailLevel,
      d.promptVersion,
      d.providerHost,
      d.model,
    ]),
  );

  @override
  Future<void> clear() => _store.remove(key);
}
