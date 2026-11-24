import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_run_marker_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';

void main() {
  late SharedPreferencesAiRunMarkerStore store;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = SharedPreferencesAiRunMarkerStore();
  });

  test('a written draft reads back with its cache key and time', () async {
    final draft = sampleAiReport(at: DateTime.utc(2026, 11, 20, 8));
    await store.write(draft);
    final read = await store.read();
    expect(read!.cacheKey, draft.cacheKey);
    expect(read.createdAtUtc, draft.createdAtUtc);
    expect(read.offsetMin, draft.offsetMin);
    expect(read.detailLevel, draft.detailLevel);
    expect(read.status, AiReportStatus.failed);
  });

  test('clear removes the marker', () async {
    await store.write(sampleAiReport(at: DateTime.utc(2026, 11, 20)));
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a corrupt marker reads as none', () async {
    await SharedPreferencesAsync().setString(
      SharedPreferencesAiRunMarkerStore.key,
      '[1, "x"]',
    );
    expect(await store.read(), isNull);
  });
}
