import 'package:metrics/metrics.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

abstract final class HealthContextBuilder {
  static const int _minSampleDays = 3;
  static const double _kgToLb = 2.20462262185;
  static const double _kmToMi = 0.621371192;

  static BuiltAiPayload build(HealthContextInput input) {
    final effWindow =
        input.detail != AiDetailLevel.full &&
            input.window == AiContextWindow.extended
        ? AiContextWindow.standard
        : input.window;
    final lang = sanitizeReplyLanguage(input.replyLanguage);
    final ring = input.coverage.hasRing;
    final dRows = _tail(input.days, effWindow.maxDays);
    final wRows = _tail(input.weeks, effWindow.maxWeeks);
    final wkRows = _filterWorkouts(input, effWindow.maxWorkouts);
    final trRows = _filterTrends(input.trends, ring, input.detail);
    final fRows = _filterFacts(
      input.facts,
      ring,
      input.detail,
      effWindow.maxFacts,
    );

    var dropped = 0;
    late Map<String, Object?> map;
    late String json;
    while (true) {
      map = _assemble(input, lang, dRows, wRows, wkRows, trRows, fRows);
      json = canonicalJsonEncode(map);
      if (estimateAiTokens(json) <= effWindow.hardCapTokens) break;
      if (!_dropOne(wRows, wkRows, fRows, dRows)) break;
      dropped++;
    }
    final userMsg = buildAnalysisUserMessage(
      kind: input.kind,
      canonicalContextJson: json,
    );
    return BuiltAiPayload(
      contextMap: map,
      canonicalContextJson: json,
      systemPrompt: aiSystemPromptV1,
      userMessage: userMsg,
      facts: List.unmodifiable(fRows),
      contextTokens: estimateAiTokens(json),
      estimatedTokens: estimateAiTokens('$aiSystemPromptV1$userMsg'),
      cacheKey: sha256Hex(
        'v$aiPromptVersion|${input.kind.wireName}|${input.detail.wireName}|$json',
      ),
      droppedCount: dropped,
    );
  }

  static List<T> _tail<T>(List<T> items, int max) => items.length <= max
      ? List<T>.of(items)
      : items.sublist(items.length - max);

  static List<AiWorkoutRow> _filterWorkouts(HealthContextInput input, int max) {
    if (input.detail == AiDetailLevel.minimal) return [];
    final keep = input.coverage.importedIncluded;
    final indexed =
        <(int, AiWorkoutRow)>[
          for (var i = 0; i < input.workouts.length; i++)
            if (keep || !input.workouts[i].isImported) (i, input.workouts[i]),
        ]..sort((a, b) {
          final da = a.$2.daysAgo < 0 ? 0 : a.$2.daysAgo;
          final db = b.$2.daysAgo < 0 ? 0 : b.$2.daysAgo;
          return da != db ? da.compareTo(db) : a.$1.compareTo(b.$1);
        });
    return [for (final (_, w) in indexed.take(max)) w];
  }

  static List<AiTrendItem> _filterTrends(
    List<AiTrendItem> items,
    bool ring,
    AiDetailLevel detail,
  ) => [
    for (final t in items)
      if (t.n >= _minSampleDays &&
          (ring || !t.metric.requiresRing) &&
          (detail != AiDetailLevel.minimal || t.metric.minimalAllowed))
        t,
  ];

  static List<HealthFact> _filterFacts(
    List<HealthFact> items,
    bool ring,
    AiDetailLevel detail,
    int maxFacts,
  ) {
    final out = <HealthFact>[];
    final used = <String>{};
    var seq = 1;
    for (final f in items) {
      if (f.days < _minSampleDays || (!ring && f.requiresRing)) continue;
      if (detail == AiDetailLevel.minimal && !f.minimalAllowed) continue;
      var id = sanitizeSafeId(f.id, fallback: 'f${out.length + 1}');
      if (!used.add(id)) {
        while (!used.add('f$seq')) {
          seq++;
        }
        id = 'f$seq';
      }
      out.add(id == f.id ? f : _copyFactWithId(f, id));
      if (out.length >= maxFacts) break;
    }
    return out;
  }

  static HealthFact _copyFactWithId(HealthFact f, String id) => HealthFact(
    id: id,
    label: f.label,
    value: f.value,
    unit: f.unit,
    family: f.family,
    days: f.days,
    requiresRing: f.requiresRing,
    minimalAllowed: f.minimalAllowed,
    isWorkoutFact: f.isWorkoutFact,
  );

  static bool _dropOne(
    List<AiWeekRow> weeks,
    List<AiWorkoutRow> workouts,
    List<HealthFact> facts,
    List<AiDayRow> days,
  ) {
    if (weeks.isNotEmpty) {
      weeks.removeAt(0);
      return true;
    }
    if (workouts.isNotEmpty) {
      workouts.removeLast();
      return true;
    }
    final wkFactIdx = facts.lastIndexWhere((f) => f.isWorkoutFact);
    if (wkFactIdx >= 0) {
      facts.removeAt(wkFactIdx);
      return true;
    }
    if (days.isNotEmpty) {
      days.removeAt(0);
      return true;
    }
    return false;
  }

  static Map<String, Object?> _assemble(
    HealthContextInput input,
    String lang,
    List<AiDayRow> days,
    List<AiWeekRow> weeks,
    List<AiWorkoutRow> workouts,
    List<AiTrendItem> trends,
    List<HealthFact> facts,
  ) {
    final d = input.detail;
    final notMin = d != AiDetailLevel.minimal;
    final ring = input.coverage.hasRing;
    final wUnit = input.units.weight;
    final end = d == AiDetailLevel.full && days.isNotEmpty
        ? days.last.date.iso
        : 'D0';
    final map = <String, Object?>{
      'schema': aiContextSchemaVersion,
      'detail': d.wireName,
      'window': {'days': days.length, 'weeks': weeks.length, 'end': end},
      'units': {
        'energy': 'kcal',
        'distance': input.units.distance.name,
        'weight': wUnit.name,
        'hrv': 'ms',
        'hr': 'bpm',
      },
      'reply_language': lang,
      'profile': _profileMap(input.profile, d),
      'coverage': {
        'ring': ring,
        'sleep_source': input.coverage.sleepSource.name,
        'days_with_ring_data': input.coverage.daysWithRingData,
        'imported_included': input.coverage.importedIncluded,
      },
      'days': _daysMap(days, d, ring, wUnit),
      'facts': [
        for (final f in facts)
          {'id': f.id, 'label': f.label, 'v': f.value, 'u': f.unit.wireName},
      ],
    };
    if (weeks.isNotEmpty) map['weeks'] = _weeksMap(weeks, d, ring, wUnit);
    if (trends.isNotEmpty) map['trends'] = _trendsList(trends);
    if (notMin && workouts.isNotEmpty) {
      map['workouts'] = [
        for (var i = 0; i < workouts.length; i++)
          _workoutMap(workouts[i], i, d, input.units.distance),
      ];
    }
    final base = _baselinesMap(input.baselines, ring);
    if (notMin && base.isNotEmpty) map['baselines'] = base;
    if (notMin && input.weighIns != null) {
      map['weigh_ins'] = _weighInsMap(input.weighIns!, wUnit);
    }
    if (notMin && input.energy != null) {
      map['energy'] = {
        'bmr_kcal': input.energy!.bmrKcal,
        'tdee_kcal_avg7': input.energy!.tdeeKcalAvg7,
        'formula': input.energy!.formula.wireName,
      };
    }
    if (input.goal != null) map['goal'] = _goalMap(input.goal!, d);
    if (notMin && input.levers.isNotEmpty) map['plan'] = _planMap(input.levers);
    if (notMin && input.food != null) map['food'] = _foodMap(input.food!);
    return map;
  }

  static Map<String, Object?> _profileMap(AiProfileInput p, AiDetailLevel d) {
    final isFull = d == AiDetailLevel.full;
    final notMin = d != AiDetailLevel.minimal;
    final ageWidth = d == AiDetailLevel.minimal ? 10 : 5;
    final ageKey = isFull ? 'age' : 'age_band';
    return {
      if (p.age != null)
        ageKey: isFull ? p.age : formatAgeBand(p.age!, width: ageWidth),
      if (notMin && p.sex != null) 'sex': p.sex!.name,
      if (notMin && p.heightCm != null) 'height_cm': p.heightCm,
      if (notMin && p.maxHr != null) 'max_hr': p.maxHr,
      if (p.stepGoal != null) 'step_goal': p.stepGoal,
    };
  }

  static Map<String, Object?> _daysMap(
    List<AiDayRow> rows,
    AiDetailLevel d,
    bool ring,
    AiWeightUnit wUnit,
  ) {
    final out = <String, Object?>{
      'd': [
        for (var i = 0; i < rows.length; i++)
          _dayLabel(rows[i], rows.length - 1 - i, d),
      ],
      'weekday': [for (final r in rows) r.weekday.name],
    };
    _col(out, 'sleep_score', rows, (r) => r.sleepScore);
    if (ring) _col(out, 'readiness', rows, (r) => r.readiness);
    _col(out, 'load', rows, (r) => r.load);
    if (ring) _col(out, 'steps', rows, (r) => r.steps);
    if (d == AiDetailLevel.minimal) {
      final deltas = _weightDeltas(rows, wUnit);
      if (deltas.isNotEmpty) out['weight_delta'] = deltas;
      return out;
    }
    final round15 = d == AiDetailLevel.standard;
    _col(out, 'sleep_min', rows, (r) => r.sleepMin);
    _col(out, 'deep_min', rows, (r) => r.deepMin);
    _col(out, 'rem_min', rows, (r) => r.remMin);
    _col(out, 'awake_min', rows, (r) => r.awakeMin);
    _col(out, 'bedtime', rows, (r) => r.bedtime?.format(round15: round15));
    _col(out, 'wake', rows, (r) => r.wake?.format(round15: round15));
    if (ring) {
      _col(out, 'rhr', rows, (r) => r.rhr);
      _col(out, 'hrv', rows, (r) => r.hrv);
      _col(out, 'stress_avg', rows, (r) => r.stressAvg);
      _col(out, 'spo2_avg', rows, (r) => r.spo2Avg);
      _col(out, 'spo2_min', rows, (r) => r.spo2Min);
      _col(out, 'active_kcal', rows, (r) => r.activeKcal);
    }
    _col(out, 'weight', rows, (r) => _weightVal(r.weightKg, wUnit));
    return out;
  }

  static Map<String, Object?> _weeksMap(
    List<AiWeekRow> rows,
    AiDetailLevel d,
    bool ring,
    AiWeightUnit wUnit,
  ) {
    final out = <String, Object?>{
      'w': [
        for (var i = 0; i < rows.length; i++)
          _relLabel('W', rows.length - 1 - i),
      ],
    };
    _col(out, 'sleep_score_avg', rows, (r) => r.sleepScoreAvg);
    if (ring) {
      _col(out, 'steps_avg', rows, (r) => r.stepsAvg);
      _col(out, 'readiness_avg', rows, (r) => r.readinessAvg);
    }
    _col(out, 'load_sum', rows, (r) => r.loadSum);
    if (d == AiDetailLevel.minimal) return out;
    _col(out, 'sleep_min_avg', rows, (r) => r.sleepMinAvg);
    if (ring) {
      _col(out, 'rhr_avg', rows, (r) => r.rhrAvg);
      _col(out, 'hrv_avg', rows, (r) => r.hrvAvg);
    }
    _col(out, 'workouts', rows, (r) => r.workouts);
    _col(out, 'weight_avg', rows, (r) => _weightVal(r.weightAvgKg, wUnit));
    return out;
  }

  static List<Map<String, Object?>> _trendsList(List<AiTrendItem> trends) => [
    for (final t in trends)
      {
        'id': sanitizeSafeId(t.id, fallback: 't.${t.metric.wireName}'),
        'metric': t.metric.wireName,
        'last28': t.last28,
        'prev28': t.prev28,
        'dir': t.dir.name,
        'n': t.n,
      },
  ];

  static Map<String, Object?> _baselinesMap(AiBaselinesInput? b, bool ring) {
    if (b == null) return const {};
    return {
      if (ring && b.rhr != null && b.rhr!.days >= _minSampleDays)
        'rhr': {'value': b.rhr!.value, 'days': b.rhr!.days},
      if (ring && b.hrv != null && b.hrv!.days >= _minSampleDays)
        'hrv': {'value': b.hrv!.value, 'days': b.hrv!.days},
      if (b.sleepMin != null && b.sleepMin!.days >= _minSampleDays)
        'sleep_min': {'value': b.sleepMin!.value, 'days': b.sleepMin!.days},
    };
  }

  static Map<String, Object?> _workoutMap(
    AiWorkoutRow w,
    int index,
    AiDetailLevel d,
    AiDistanceUnit distUnit,
  ) {
    final imp = w.isImported;
    final isMi = distUnit == AiDistanceUnit.mi;
    final dist = _scale(w.distanceKm, isMi, _kmToMi, 100);
    return {
      'id': sanitizeSafeId(w.id, fallback: 'wk.${index + 1}'),
      'd': d == AiDetailLevel.full ? w.date.iso : _relLabel('D', w.daysAgo),
      'type': w.type.activityType,
      'min': w.minutes,
      'avg_hr': imp ? null : w.avgHr,
      'max_hr': imp ? null : w.maxHr,
      'z': imp ? null : w.zones,
      isMi ? 'mi' : 'km': imp ? null : dist,
      'kcal': imp ? null : w.kcal,
      'src': imp ? 'imported' : 'openring',
      if (d == AiDetailLevel.full && imp) 'app': sanitizeSourceApp(w.sourceApp),
    };
  }

  static Map<String, Object?> _weighInsMap(
    AiWeighInsSummary wi,
    AiWeightUnit u,
  ) {
    final isLb = u == AiWeightUnit.lb;
    final prefix = isLb ? 'lb_per_week' : 'kg_per_week';
    return {
      'n30': wi.n30,
      'trend_last': _weightVal(wi.trendLastKg, u),
      'days_since_last': wi.daysSinceLast,
      if (wi.kgPerWeek != null)
        prefix: _scale(wi.kgPerWeek, isLb, _kgToLb, 100),
      if (wi.kgPerWeekLow != null)
        '${prefix}_low': _scale(wi.kgPerWeekLow, isLb, _kgToLb, 100),
      if (wi.kgPerWeekHigh != null)
        '${prefix}_high': _scale(wi.kgPerWeekHigh, isLb, _kgToLb, 100),
    };
  }

  static Map<String, Object?> _goalMap(AiGoalSummary g, AiDetailLevel d) => {
    'type': switch (g.kind) {
      GoalKind.loseFat => 'lose_fat',
      GoalKind.getFitter => 'get_fitter',
      GoalKind.sleepBetter => 'sleep_better',
    },
    'status': g.status.name,
    'started': d == AiDetailLevel.full
        ? g.startedDate.iso
        : _relLabel('D', g.startedDaysAgo),
    'block_week': g.blockWeek,
    'block_weeks': g.blockWeeks,
    if (d != AiDetailLevel.minimal && g.rateTargetPct != null)
      'rate_target_pct': g.rateTargetPct,
  };

  static Map<String, Object?> _planMap(List<AiPlanLever> levers) => {
    'week': 'W0',
    'levers': [
      for (var i = 0; i < levers.length; i++)
        {
          'id': sanitizeSafeId(levers[i].id, fallback: 'p.${i + 1}'),
          'lever': _leverName(levers[i].kind),
          'target': _leverTargetValue(levers[i].target),
          levers[i].isDaily ? 'days_met' : 'met': levers[i].met,
        },
    ],
  };

  static Map<String, Object?> _foodMap(AiFoodSummary food) => {
    'complete_days': food.completeDays,
    if (food.plateScore != null) 'plate_score': food.plateScore,
    if (food.windowMedianMin != null) 'window_median_min': food.windowMedianMin,
    if (food.lastMealToSleepMin != null)
      'last_meal_to_sleep_min': food.lastMealToSleepMin,
  };

  static Object _leverTargetValue(AiLeverTarget target) => switch (target) {
    AiLeverIntTarget(:final value) => value,
    AiLeverTimeTarget(:final time) => time.format(round15: false),
  };

  static String _dayLabel(AiDayRow r, int ago, AiDetailLevel d) =>
      d == AiDetailLevel.full ? r.date.iso : _relLabel('D', ago);

  static String _relLabel(String prefix, int ago) {
    final safe = ago < 0 ? 0 : ago;
    return safe == 0 ? '${prefix}0' : '$prefix-$safe';
  }

  static List<double?> _weightDeltas(List<AiDayRow> rows, AiWeightUnit u) {
    final weights = [for (final r in rows) _weightVal(r.weightKg, u)];
    final base = weights.firstWhere((w) => w != null, orElse: () => null);
    if (base == null) return const [];
    return [
      for (final w in weights)
        _scale(w == null ? null : w - base, false, 1, 10),
    ];
  }

  static double? _weightVal(double? kg, AiWeightUnit u) =>
      _scale(kg, u == AiWeightUnit.lb, _kgToLb, 10);

  static double? _scale(double? v, bool convert, double factor, int dec) {
    if (v == null) return null;
    final scaled = convert ? v * factor : v;
    return (scaled * dec).round() / dec;
  }

  static String _leverName(LeverKind kind) => switch (kind) {
    LeverKind.strengthDays => 'strength_days',
    LeverKind.sleepWindow => 'sleep_window',
    LeverKind.steps => 'steps',
    LeverKind.effortPoints => 'effort_points',
    LeverKind.wakeTime => 'wake_time',
  };

  static void _col<T>(
    Map<String, Object?> out,
    String key,
    List<T> rows,
    Object? Function(T) pick,
  ) {
    final vals = [for (final r in rows) pick(r)];
    if (vals.any((v) => v != null)) out[key] = vals;
  }
}
