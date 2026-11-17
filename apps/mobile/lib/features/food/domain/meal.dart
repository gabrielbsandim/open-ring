import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';

final class MealDraft {
  const new({
    required this.at,
    required this.offsetMinutes,
    this.kind,
    this.tags = const MealTags(),
    this.last = false,
  });

  /// The capture instant.
  final DateTime at;
  final int offsetMinutes;
  final MealKind? kind;
  final MealTags tags;
  final bool last;
}

@immutable
final class Meal {
  const new({
    required this.id,
    required this.at,
    required this.offsetMinutes,
    required this.createdAt,
    this.kind,
    this.tags = const MealTags(),
    this.last = false,
    this.photo,
  });

  final int id;

  /// The capture instant, in UTC.
  final DateTime at;
  final int offsetMinutes;
  final MealKind? kind;
  final MealTags tags;
  final bool last;

  /// A bare file name in the photo store, null when there is none.
  final String? photo;
  final DateTime createdAt;

  /// The meal at its capture wall clock, as a UTC flagged DateTime whose
  /// fields are local time; sleep onsets compared with it must be built so.
  MealEntry get entry => MealEntry(
    at: DateTime.fromMillisecondsSinceEpoch(
      at.millisecondsSinceEpoch +
          offsetMinutes * Duration.millisecondsPerMinute,
      isUtc: true,
    ),
    kind: kind,
    tags: tags,
    last: last,
  );

  @override
  bool operator ==(Object other) =>
      other is Meal &&
      other.id == id &&
      other.at == at &&
      other.offsetMinutes == offsetMinutes &&
      other.kind == kind &&
      _tagsOf(other.tags) == _tagsOf(tags) &&
      other.last == last &&
      other.photo == photo &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    at,
    offsetMinutes,
    kind,
    _tagsOf(tags),
    last,
    photo,
    createdAt,
  );
}

Object _tagsOf(MealTags t) => (
  t.protein,
  t.caffeine,
  t.heavy,
  t.fried,
  t.sugar,
  t.veg,
  t.alcohol,
  t.processed,
  t.place,
);

enum MealFlag { protein, caffeine, heavy, fried, sugar }

// Marks a nullable tag the edit leaves as it is, since null clears it.
const Object _keep = Object();

/// The kind, tags and last meal switch the saved sheet edits on a meal.
@immutable
final class MealEdit {
  const new({this.kind, this.tags = const MealTags(), this.last = false});

  new of(Meal meal) : this(kind: meal.kind, tags: meal.tags, last: meal.last);

  final MealKind? kind;
  final MealTags tags;
  final bool last;

  bool flag(MealFlag flag) => switch (flag) {
    MealFlag.protein => tags.protein,
    MealFlag.caffeine => tags.caffeine,
    MealFlag.heavy => tags.heavy,
    MealFlag.fried => tags.fried,
    MealFlag.sugar => tags.sugar,
  };

  MealEdit withKind(MealKind? kind) =>
      MealEdit(kind: kind, tags: tags, last: last);

  // Positional like the other with calls, so a switch passes its value as is.
  // ignore: avoid_positional_boolean_parameters
  MealEdit withLast(bool last) => MealEdit(kind: kind, tags: tags, last: last);

  // Positional so a FilterChip's onSelected value passes through as is.
  // ignore: avoid_positional_boolean_parameters
  MealEdit withFlag(MealFlag flag, bool on) => _withTags(flag: flag, on: on);

  MealEdit withVeg(MealVeg? veg) => _withTags(veg: veg);

  MealEdit withAlcohol(MealAlcohol? alcohol) => _withTags(alcohol: alcohol);

  MealEdit withProcessed(MealProcessed? processed) =>
      _withTags(processed: processed);

  MealEdit withPlace(MealPlace? place) => _withTags(place: place);

  bool sameAs(Meal meal) =>
      meal.kind == kind &&
      meal.last == last &&
      _tagsOf(meal.tags) == _tagsOf(tags);

  /// The row [meal] becomes with this edit, at its own capture time.
  MealDraft draftOf(Meal meal) => MealDraft(
    at: meal.at,
    offsetMinutes: meal.offsetMinutes,
    kind: kind,
    tags: tags,
    last: last,
  );

  MealEdit _withTags({
    MealFlag? flag,
    bool on = false,
    Object? veg = _keep,
    Object? alcohol = _keep,
    Object? processed = _keep,
    Object? place = _keep,
  }) {
    bool pick(MealFlag other) => other == flag ? on : this.flag(other);
    T keep<T>(Object? value, T old) =>
        identical(value, _keep) ? old : value as T;
    return MealEdit(
      kind: kind,
      last: last,
      tags: MealTags(
        protein: pick(MealFlag.protein),
        caffeine: pick(MealFlag.caffeine),
        heavy: pick(MealFlag.heavy),
        fried: pick(MealFlag.fried),
        sugar: pick(MealFlag.sugar),
        veg: keep(veg, tags.veg),
        alcohol: keep(alcohol, tags.alcohol),
        processed: keep(processed, tags.processed),
        place: keep(place, tags.place),
      ),
    );
  }
}
