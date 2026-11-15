import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/level_view.dart';

final levelTrackProvider = FutureProvider<LevelTrack>((ref) async {
  final (history, tags) = await (
    ref.watch(dayScoreHistoryProvider.future),
    ref.watch(dayTagsProvider.future),
  ).wait;
  return closedLevelTrack(history, tags.keys.toSet());
});
