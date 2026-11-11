import 'package:open_ring/features/workout/domain/workout_history.dart';

// Walks the sources in priority order and keeps a workout unless one from a
// higher source overlaps it; two workouts are never merged.
List<WorkoutEntry> selectWorkouts(
  Iterable<WorkoutEntry> entries,
  List<String> priority,
) {
  int rank(String source) {
    final index = priority.indexOf(source);
    if (index < 0) return priority.length;
    return index;
  }

  final ranked = entries.indexed.toList()
    ..sort((a, b) {
      final byRank = rank(a.$2.source).compareTo(rank(b.$2.source));
      if (byRank != 0) return byRank;
      return a.$1.compareTo(b.$1);
    });
  final kept = <WorkoutEntry>[];
  for (final (_, entry) in ranked) {
    final covered = kept.any(
      (other) => other.source != entry.source && other.overlaps(entry),
    );
    if (!covered) kept.add(entry);
  }
  return kept..sort((a, b) => b.start.compareTo(a.start));
}
