import 'dart:convert';
import 'dart:math' as math;

import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesAiRunMarkerStore implements AiRunMarkerStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'ai_run_marker';
  static const monthKey = 'ai_month_tokens';
  static const photoUsesKey = 'ai_photo_day_uses';
  static const Set<String> keys = {key, monthKey, photoUsesKey};

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
        status: AiReportStatus.cancelled,
        errorKind: 'cancelled',
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

  @override
  Future<int> monthTokens(String month) => _count(monthKey, month);

  @override
  Future<void> addMonthTokens(String month, int tokens) =>
      _add(monthKey, month, tokens);

  @override
  Future<int> photoUses(String day) => _count(photoUsesKey, day);

  @override
  Future<void> addPhotoUses(String day, int delta) =>
      _add(photoUsesKey, day, delta);

  Future<int> _count(String key, String period) async {
    final saved = await _store.getStringList(key);
    if (saved == null || saved.length != 2 || saved.first != period) return 0;
    return int.tryParse(saved.last) ?? 0;
  }

  Future<void> _add(String key, String period, int delta) async {
    final next = math.max(0, await _count(key, period) + delta);
    await _store.setStringList(key, [period, '$next']);
  }
}
