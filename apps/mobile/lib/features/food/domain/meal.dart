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
