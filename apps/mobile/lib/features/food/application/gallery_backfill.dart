import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/exif.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';

const _duplicateWindow = Duration(minutes: 2);
const _oldAge = Duration(days: 365);

enum GalleryItemStatus {
  ready,
  nearDuplicate,
  needsTime,
  tooOld,
  skipped,
  unreadable,
}

enum GalleryImportPhase { idle, picking, review, saving, done }

@immutable
final class GalleryItem {
  const new({
    required this.index,
    required this.strippedBytes,
    required this.status,
    this.captureAt,
    this.offsetMinutes,
    this.timeFromPhoto = false,
    this.duplicateOfAt,
    this.duplicateOfOffsetMinutes,
    this.duplicateConfirmed = false,
    this.oldConfirmed = false,
    this.skipped = false,
  });

  final int index;
  final Uint8List strippedBytes;
  final DateTime? captureAt;
  final int? offsetMinutes;
  final bool timeFromPhoto;
  final DateTime? duplicateOfAt;
  final int? duplicateOfOffsetMinutes;
  final bool duplicateConfirmed;
  final bool oldConfirmed;
  final bool skipped;
  final GalleryItemStatus status;
}

@immutable
final class GalleryImportState {
  const new({
    this.phase = GalleryImportPhase.idle,
    this.items = const [],
    this.savedCount = 0,
    this.noSpace = false,
    this.pickFailed = false,
    this.saveFailed = false,
  });

  final GalleryImportPhase phase;
  final List<GalleryItem> items;
  final int savedCount;
  final bool noSpace;
  final bool pickFailed;
  final bool saveFailed;

  int get readyCount =>
      items.where((item) => item.status == GalleryItemStatus.ready).length;

  int get openCount => items
      .where(
        (item) =>
            item.status == GalleryItemStatus.nearDuplicate ||
            item.status == GalleryItemStatus.needsTime ||
            item.status == GalleryItemStatus.tooOld,
      )
      .length;
}

final NotifierProvider<GalleryBackfill, GalleryImportState>
galleryBackfillProvider = NotifierProvider(GalleryBackfill.new);

class GalleryBackfill extends Notifier<GalleryImportState> {
  int _generation = 0;
  final Map<int, Meal> _knownMeals = {};
  final Set<LocalDate> _loadedDays = {};

  @override
  GalleryImportState build() {
    ref.watch(foodEnabledProvider);
    _generation++;
    _knownMeals.clear();
    _loadedDays.clear();
    return const GalleryImportState();
  }

  /// Opens the gallery picker, strips EXIF upfront, and classifies picks.
  Future<void> pick() async {
    if (state.phase == GalleryImportPhase.picking ||
        state.phase == GalleryImportPhase.saving) {
      return;
    }
    if (!ref.read(foodEnabledProvider)) return;
    final gen = ++_generation;
    _knownMeals.clear();
    _loadedDays.clear();
    state = const GalleryImportState(phase: GalleryImportPhase.picking);
    final gallery = ref.read(mealGalleryProvider);
    final meals = ref.read(mealStoreProvider);
    final List<Uint8List> rawPhotos;
    try {
      rawPhotos = await gallery.pickPhotos();
    } on Object {
      if (!ref.mounted || _generation != gen) return;
      state = const GalleryImportState(pickFailed: true);
      return;
    }
    if (!_active(gen)) return;
    if (rawPhotos.isEmpty) {
      state = const GalleryImportState();
      return;
    }
    final nowUtc = ref.read(clockProvider)().toUtc();
    final prepared = [
      for (var i = 0; i < rawPhotos.length; i++)
        _prepareItem(i, rawPhotos[i], nowUtc),
    ];
    for (final (from, to) in _mergedRanges(prepared)) {
      if (!await _loadRange(meals, from, to, gen)) return;
    }
    if (!_active(gen)) return;
    state = GalleryImportState(
      phase: GalleryImportPhase.review,
      items: _reclassify(prepared, _knownMeals.values, nowUtc),
    );
  }

  void confirmAnotherMeal(int index) {
    final item = _reviewItem(index);
    if (item == null || item.skipped) return;
    _replaceItem(index, _cloneItem(item, duplicateConfirmed: true));
  }

  void confirmOld(int index) {
    final item = _reviewItem(index);
    if (item == null || item.skipped) return;
    _replaceItem(index, _cloneItem(item, oldConfirmed: true));
  }

  /// Sets a non-future local capture time for [index] and reloads its day window.
  Future<bool> setManualTime(int index, DateTime localTime) async {
    final item = _reviewItem(index);
    if (item == null) return false;
    final gen = _generation;
    final local = localTime.toLocal();
    final atUtc = local.toUtc();
    if (atUtc.isAfter(ref.read(clockProvider)().toUtc())) return false;
    final day = foodDay(local);
    final loaded =
        _loadedDays.contains(day.addDays(-1)) &&
        _loadedDays.contains(day) &&
        _loadedDays.contains(day.addDays(1));
    if (!loaded &&
        !await _loadRange(
          ref.read(mealStoreProvider),
          day.addDays(-1),
          day.addDays(1),
          gen,
        )) {
      return false;
    }
    final current = _reviewItem(index);
    if (current == null || _generation != gen) return false;
    _replaceItem(
      index,
      GalleryItem(
        index: current.index,
        strippedBytes: current.strippedBytes,
        captureAt: atUtc,
        offsetMinutes: local.timeZoneOffset.inMinutes,
        status: current.status,
      ),
    );
    return true;
  }

  void skip(int index) {
    final item = _reviewItem(index);
    if (item == null) return;
    _replaceItem(
      index,
      _cloneItem(item, skipped: true, duplicateOf: (null, null)),
    );
  }

  /// Commits every ready item atomically; stops cleanly on a full disk.
  Future<void> saveReady() async {
    if (state.phase != GalleryImportPhase.review) return;
    if (!ref.read(foodEnabledProvider)) return;
    if (state.readyCount == 0) {
      state = GalleryImportState(
        phase: GalleryImportPhase.done,
        items: state.items,
      );
      return;
    }
    final gen = _generation;
    final ready = state.items
        .where((item) => item.status == GalleryItemStatus.ready)
        .toList();
    final saver = ref.read(mealPhotoSaverProvider);
    final revision = ref.read(dataRevisionProvider.notifier);
    state = GalleryImportState(
      phase: GalleryImportPhase.saving,
      items: state.items,
    );
    var saved = 0;
    var noSpace = false;
    var failed = false;
    for (final item in ready) {
      if (!_active(gen)) return;
      final source = item.timeFromPhoto
          ? TimeSource.photo
          : TimeSource.returned;
      final result = await saver.savePrepared(
        item.strippedBytes,
        at: item.captureAt!,
        offsetMinutes: item.offsetMinutes!,
        source: source,
        keepRowOnNoSpace: false,
      );
      if (!_active(gen)) return;
      if (result.outcome == SaveOutcome.saved) {
        saved++;
        continue;
      }
      if (result.outcome == SaveOutcome.noSpace) {
        noSpace = true;
        break;
      }
      failed = true;
    }
    if (saved > 0) revision.bump();
    state = GalleryImportState(
      phase: GalleryImportPhase.done,
      items: state.items,
      savedCount: saved,
      noSpace: noSpace,
      saveFailed: failed,
    );
  }

  void reset() {
    _generation++;
    _knownMeals.clear();
    _loadedDays.clear();
    state = const GalleryImportState();
  }

  bool _active(int gen) {
    if (!ref.mounted || _generation != gen) return false;
    if (ref.read(foodEnabledProvider)) return true;
    state = const GalleryImportState();
    return false;
  }

  GalleryItem? _reviewItem(int index) {
    if (state.phase != GalleryImportPhase.review) return null;
    if (index < 0 || index >= state.items.length) return null;
    if (!ref.mounted || !ref.read(foodEnabledProvider)) return null;
    final item = state.items[index];
    return item.status == GalleryItemStatus.unreadable ? null : item;
  }

  void _replaceItem(int index, GalleryItem replacement) {
    final next = List<GalleryItem>.of(state.items)..[index] = replacement;
    final nowUtc = ref.read(clockProvider)().toUtc();
    state = GalleryImportState(
      phase: state.phase,
      items: _reclassify(next, _knownMeals.values, nowUtc),
      savedCount: state.savedCount,
      noSpace: state.noSpace,
      pickFailed: state.pickFailed,
      saveFailed: state.saveFailed,
    );
  }

  Future<bool> _loadRange(
    MealStore meals,
    LocalDate from,
    LocalDate to,
    int gen,
  ) async {
    final List<Meal> fetched;
    try {
      fetched = await meals.between(from, to);
    } on Object {
      if (!ref.mounted || _generation != gen) return false;
      if (state.phase == GalleryImportPhase.picking) {
        state = const GalleryImportState(pickFailed: true);
      }
      return false;
    }
    if (!_active(gen)) return false;
    for (final meal in fetched) {
      _knownMeals[meal.id] = meal;
    }
    for (var d = from; d.compareTo(to) <= 0; d = d.addDays(1)) {
      _loadedDays.add(d);
    }
    return true;
  }
}

GalleryItem _cloneItem(
  GalleryItem item, {
  (DateTime?, int?)? duplicateOf,
  bool? duplicateConfirmed,
  bool? oldConfirmed,
  bool? skipped,
  GalleryItemStatus? status,
}) => GalleryItem(
  index: item.index,
  strippedBytes: item.strippedBytes,
  captureAt: item.captureAt,
  offsetMinutes: item.offsetMinutes,
  timeFromPhoto: item.timeFromPhoto,
  duplicateOfAt: duplicateOf != null ? duplicateOf.$1 : item.duplicateOfAt,
  duplicateOfOffsetMinutes: duplicateOf != null
      ? duplicateOf.$2
      : item.duplicateOfOffsetMinutes,
  duplicateConfirmed: duplicateConfirmed ?? item.duplicateConfirmed,
  oldConfirmed: oldConfirmed ?? item.oldConfirmed,
  skipped: skipped ?? item.skipped,
  status: status ?? item.status,
);

GalleryItem _prepareItem(int index, Uint8List raw, DateTime nowUtc) {
  final Uint8List stripped;
  try {
    stripped = stripExif(raw);
  } on FormatException {
    return GalleryItem(
      index: index,
      strippedBytes: Uint8List(0),
      status: GalleryItemStatus.unreadable,
    );
  }
  final resolved = resolveExifTime(exifCaptureTime(raw));
  if (resolved == null || resolved.at.isAfter(nowUtc.add(_duplicateWindow))) {
    return GalleryItem(
      index: index,
      strippedBytes: stripped,
      status: GalleryItemStatus.needsTime,
    );
  }
  return GalleryItem(
    index: index,
    strippedBytes: stripped,
    captureAt: resolved.at,
    offsetMinutes: resolved.offset,
    timeFromPhoto: true,
    status: GalleryItemStatus.ready,
  );
}

List<(LocalDate, LocalDate)> _mergedRanges(List<GalleryItem> items) {
  final windows = <(LocalDate, LocalDate)>[];
  for (final item in items) {
    if (item.captureAt == null || item.offsetMinutes == null) continue;
    final wall = DateTime.fromMillisecondsSinceEpoch(
      item.captureAt!.millisecondsSinceEpoch +
          item.offsetMinutes! * Duration.millisecondsPerMinute,
      isUtc: true,
    );
    final day = foodDay(wall);
    windows.add((day.addDays(-1), day.addDays(1)));
  }
  if (windows.isEmpty) return const [];
  windows.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(LocalDate, LocalDate)>[windows.first];
  for (final next in windows.skip(1)) {
    final prev = merged.last;
    if (next.$1.compareTo(prev.$2.addDays(1)) <= 0) {
      final end = next.$2.compareTo(prev.$2) > 0 ? next.$2 : prev.$2;
      merged[merged.length - 1] = (prev.$1, end);
      continue;
    }
    merged.add(next);
  }
  return merged;
}

List<GalleryItem> _reclassify(
  List<GalleryItem> items,
  Iterable<Meal> savedMeals,
  DateTime nowUtc,
) {
  final out = <GalleryItem>[];
  final accepted = <({DateTime at, int offset})>[];
  for (final item in items) {
    final evaluated = _classifyItem(item, savedMeals, accepted, nowUtc);
    out.add(evaluated);
    if (evaluated.status == GalleryItemStatus.ready) {
      accepted.add((
        at: evaluated.captureAt!,
        offset: evaluated.offsetMinutes!,
      ));
    }
  }
  return out;
}

GalleryItem _classifyItem(
  GalleryItem item,
  Iterable<Meal> savedMeals,
  List<({DateTime at, int offset})> accepted,
  DateTime nowUtc,
) {
  if (item.status == GalleryItemStatus.unreadable) return item;
  if (item.skipped) {
    return _cloneItem(
      item,
      duplicateOf: (null, null),
      status: GalleryItemStatus.skipped,
    );
  }
  final at = item.captureAt;
  final offset = item.offsetMinutes;
  if (at == null || offset == null) {
    return _cloneItem(
      item,
      duplicateOf: (null, null),
      status: GalleryItemStatus.needsTime,
    );
  }
  final dup = _findDuplicate(at, savedMeals, accepted);
  final status = _statusFor(item, at, dup, nowUtc);
  return _cloneItem(item, duplicateOf: (dup?.at, dup?.offset), status: status);
}

GalleryItemStatus _statusFor(
  GalleryItem item,
  DateTime at,
  ({DateTime at, int offset})? dup,
  DateTime nowUtc,
) {
  if (dup != null && !item.duplicateConfirmed) {
    return GalleryItemStatus.nearDuplicate;
  }
  if (nowUtc.difference(at) > _oldAge && !item.oldConfirmed) {
    return GalleryItemStatus.tooOld;
  }
  return GalleryItemStatus.ready;
}

({DateTime at, int offset})? _findDuplicate(
  DateTime at,
  Iterable<Meal> savedMeals,
  List<({DateTime at, int offset})> accepted,
) {
  for (final meal in savedMeals) {
    if (at.difference(meal.at).abs() <= _duplicateWindow) {
      return (at: meal.at, offset: meal.offsetMinutes);
    }
  }
  for (final prior in accepted) {
    if (at.difference(prior.at).abs() <= _duplicateWindow) return prior;
  }
  return null;
}
