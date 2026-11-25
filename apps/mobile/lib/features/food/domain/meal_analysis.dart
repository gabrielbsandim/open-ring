import 'dart:convert';

import 'package:open_ring/features/ai/domain/ai_cost.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';

enum MealAnalysisStatus {
  queued('queued'),
  sending('sending'),
  done('done'),
  notFood('not_food'),
  rejected('rejected'),
  failed('failed'),
  skipped('skipped');

  new(this.wire);

  final String wire;

  /// A stored answer the cache may hand back without a new request.
  bool get isAnswer => this == done || this == notFood;

  static MealAnalysisStatus fromWire(String raw) =>
      values.firstWhere((s) => s.wire == raw, orElse: () => failed);
}

enum MealItemOrigin { model, user }

abstract final class MealAnalysisErrorKind {
  static const String expired = 'expired';
  static const String targetChanged = 'target_changed';
  static const String interrupted = 'interrupted';
  static const String keptOnPhone = 'kept_on_phone';
  static const String noConsent = 'no_consent';
  static const String photoMissing = 'photo_missing';
  static const String urlRejected = 'url_rejected';
  static const String cancelled = 'cancelled';
  static const String unexpected = 'unexpected';
}

typedef MealAnalysisTarget = ({
  String providerHost,
  String model,
  int promptVersion,
  int outputSchema,
});

typedef MealSentPhoto = ({String sha256, int width, int height, int bytes});

typedef MealAnalysisItem = ({
  int id,
  String name,
  MealPhotoMeasure measure,
  int countX2,
  int grams,
  MealItemOrigin origin,
  bool confirmed,
});

/// What one finished request wrote: `done`, `not_food` or `rejected`.
typedef MealAnalysisAnswer = ({
  MealAnalysisStatus status,
  MealSentPhoto sent,
  MealPhotoSuggestion? suggestion,
  MealPhotoConfidence? confidence,
  String? rawText,
  AiTokenUsage? usage,
  AiCost? cost,
  String? errorKind,
});

/// One stored analysis; `items` holds user and model items by position.
typedef MealAnalysis = ({
  int id,
  int mealId,
  String photoName,
  MealAnalysisStatus status,
  MealAnalysisTarget target,
  DateTime queuedAt,
  DateTime updatedAt,
  MealSentPhoto? sent,
  String? resultJson,
  String? rawText,
  MealPhotoConfidence? confidence,
  int attempts,
  String? errorKind,
  bool hiddenOil,
  bool hiddenSauce,
  bool hiddenSugar,
  List<MealAnalysisItem> items,
});

extension MealAnalysisResult on MealAnalysis {
  MealPhotoSuggestion? get suggestion {
    final raw = resultJson;
    if (raw == null) return null;
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?>) return null;
    return MealPhotoSuggestion.fromJson(json);
  }
}
