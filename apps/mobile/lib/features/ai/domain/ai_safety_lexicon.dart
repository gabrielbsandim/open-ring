abstract final class AiSafetyLexicon {
  static const Set<String> supportedBaseLocales = {
    'de',
    'en',
    'es',
    'fr',
    'id',
    'it',
    'ja',
    'pt',
    'ru',
    'zh',
  };
  static const _commaLocales = {'de', 'es', 'fr', 'id', 'it', 'pt', 'ru'};
  static const _cjkLocales = {'ja', 'zh'};
  static const _alpha = r'\p{sc=Latin}\p{sc=Cyrillic}';

  static const _medicalStems = {
    'en': 'diagnos|disease|disorder|syndrome|apnea|arrhythmia|fibrillation|hypertension|diabetes|infection|medication|dosage|dose|supplement|prescri|pharmac|antibiotic|insulin|steroid|antidepressant',
    'pt': 'diagnós|diagnos|doença|distúrbio|disturbio|síndrome|sindrome|apneia|arritmia|fibrilaç|fibrilac|hipertens|diabet|infecç|infecc|remédio|remedio|medicament|dosagem|dose|suplement|prescri|farmác|farmac|antibiót|antibiot|insulina',
    'es': 'diagnóst|diagnost|enfermedad|trastorno|síndrome|sindrome|apnea|arritmia|fibrilac|hipertens|diabet|infecc|medicament|dosis|dosific|suplement|prescri|fármac|farmac|antibiót|antibiot|insulina',
    'fr': 'diagnos|maladie|trouble|syndrome|apnée|apnee|arythmie|fibrillation|hypertension|diabète|diabete|infection|médicament|medicament|posologie|dosage|dose|supplément|supplement|prescri|ordonnance|antibiotique|insuline',
    'de': 'diagnos|krankheit|erkrankung|störung|storung|syndrom|apnoe|arrhythmie|vorhofflimmern|bluthochdruck|hypertonie|diabetes|infektion|medikament|dosier|dosis|nahrungsergänzung|verschreib|antibiotik|insulin',
    'id': 'diagnos|penyakit|gangguan|sindrom|apnea|aritmia|fibrilasi|hipertensi|diabetes|infeksi|obat|dosis|suplemen|antibiotik|insulin',
    'it': 'diagnos|malattia|disturbo|sindrome|apnea|aritmia|fibrillaz|ipertensione|diabete|infezion|farmac|medicinal|dosaggio|dose|integrator|prescri|antibiotic|insulina',
    'ja': '診断|疾患|病気|障害|症候群|無呼吸|不整脈|心房細動|高血圧|糖尿病|感染|薬|服薬|用量|投与|サプリメント|処方|抗生物質|インスリン',
    'ru': 'диагноз|болезн|заболеван|расстройств|синдром|апноэ|аритми|фибрилляц|гипертон|гипертенз|диабет|инфекц|лекарств|медикамент|препарат|дозировк|доза|дозы|дозу|добавк|антибиотик|инсулин',
    'zh': '诊断|疾病|病症|障碍|综合征|呼吸暂停|心律失常|房颤|高血压|糖尿病|感染|药物|服药|用药|剂量|补充剂|保健品|处方|抗生素|胰岛素',
  };

  static const _causalPhrases = {
    'en': 'because|caused|causes|causing|due to|resulted in|leads to|led to|therefore|as a result',
    'pt': 'porque|causa|causou|causam|causar|causaram|causando|por causa|devido a|levou a|provocou|resultou em|portanto',
    'es': 'porque|causa|causó|causo|causan|causar|causaron|debido a|por culpa|provocó|provoco|llevó a|por lo tanto',
    'fr': 'parce que|à cause de|a cause de|en raison de|causé|cause|causent|provoqué|provoque|entraîné|donc',
    'de': 'weil|wegen|aufgrund|verursacht|verursachte|führte zu|fuhrte zu|deshalb|daher|dadurch',
    'id': 'karena|disebabkan|menyebabkan|sebabkan|akibat|sehingga|oleh karena itu',
    'it': 'perché|perche|a causa di|causato|causa|causano|dovuto a|provocato|ha portato a|quindi',
    'ja': 'のため|原因|引き起こ|によって低下|によって上昇|だから|したがって',
    'ru': 'потому что|из-за|вызвало|вызвал|вызвала|вызвали|вызывает|привело к|вследствие|поэтому',
    'zh': '因为|导致|引起|造成|由于|因此|所以',
  };

  static const _periodUnitPatterns = {
    'en': 'days?|nights?|weeks?|mornings?',
    'pt': 'dias?|noites?|semanas?|manh[aã]s?',
    'es': 'd[ií]as?|noches?|semanas?|ma[nñ]anas?',
    'fr': 'jours?|nuits?|semaines?|matins?|matin[eé]es?',
    'de': 'tag(?:en?)?|n[aä]cht(?:en?)?|wochen?|morgen',
    'id': 'hari|malam|minggu|pekan|pagi',
    'it': 'giorn[io]|nott[ei]|settiman[ae]|mattin[ae]',
    'ja': '日間?|晩|夜|週間?|朝',
    'ru': 'д(?:ень|ня|ней)|ноч(?:ь|и|ей)|недел(?:я|и|ь|ю)|утр[ао]?',
    'zh': '天|日|晚|夜|周|週|星期|早上|早晨',
  };

  static const _actionUnitPatterns = {
    'en': 'min(?:s|utes?)?|hours?|days?|nights?|weeks?|steps?',
    'pt': 'min(?:utos?)?|horas?|dias?|noites?|semanas?|passos?',
    'es': 'min(?:utos?)?|horas?|d[ií]as?|noches?|semanas?|pasos?',
    'fr': 'min(?:utes?)?|heures?|jours?|nuits?|semaines?|pas',
    'de': 'min(?:uten?)?|stunden?|tag(?:en?)?|n[aä]cht(?:en?)?|wochen?|schritt(?:en?)?',
    'id': 'menit|min|jam|hari|malam|minggu|pekan|langkah',
    'it': 'min(?:ut[io])?|or[ae]|giorn[io]|nott[ei]|settiman[ae]|pass[io]',
    'ja': '分間?|時間|日間?|晩|夜|週間?|歩',
    'ru': 'мин(?:ут[ауы]?)?|час(?:а|ов)?|д(?:ень|ня|ней)|ноч(?:ь|и|ей)|недел(?:я|и|ь|ю)|шаг(?:а|ов)?',
    'zh': '分钟|分鐘|分|小时|小時|天|日|晚|周|週|步',
  };

  static final _shortMed = RegExp(
    '(?<![$_alpha])(?:mg|mcg|mmhg|rx)(?![$_alpha])',
    caseSensitive: false,
    unicode: true,
  );
  static final _forbiddenVitalUnit = RegExp(
    r'^\s*(%|(?:bpm|ms|kg|lbs?|kcal|cal|kj|mg|mcg|ug|µg|ml|iu|mmhg|spo2|'
    'vo2|bmi|imc|g|oz|уд/мин|мс|кг|ккал|мг|мкг|мл|мм)(?![$_alpha])|'
    'カロリー|キロカロリー|ミリグラム|千卡|大卡|毫克|微克|毫升|公斤|磅)',
    caseSensitive: false,
    unicode: true,
  );
  static final _urlOrLink = RegExp(r'https?:|www\.|\]\(', caseSensitive: false);
  static final Map<String, RegExp> _causalCache = _cache(_causalPhrases);
  static final Map<String, RegExp> _periodCache = _unitCache(
    _periodUnitPatterns,
  );
  static final Map<String, RegExp> _actionCache = _unitCache(
    _actionUnitPatterns,
  );

  static String baseLocale(String replyLanguage) {
    final norm = replyLanguage.trim().replaceAll('_', '-').toLowerCase();
    final sep = norm.indexOf('-');
    final base = sep < 0 ? norm : norm.substring(0, sep);
    return supportedBaseLocales.contains(base) ? base : 'en';
  }

  static bool usesCommaDecimal(String replyLanguage) =>
      _commaLocales.contains(baseLocale(replyLanguage));

  static String? findMedicalTerm(String text, String replyLanguage) {
    final lower = text.toLowerCase();
    final shortMatch = _shortMed.firstMatch(lower);
    if (shortMatch != null) return shortMatch.group(0);
    for (final loc in _localesFor(replyLanguage)) {
      for (final stem in _medicalStems[loc]!.split('|')) {
        if (lower.contains(stem)) return stem;
      }
    }
    return null;
  }

  static String? findCausalPhrase(String text, String replyLanguage) {
    final lower = text.toLowerCase();
    for (final loc in _localesFor(replyLanguage)) {
      final match = _causalCache[loc]?.firstMatch(lower);
      if (match != null) return match.group(0);
    }
    return null;
  }

  static bool hasPeriodUnitAfter(String after, String replyLanguage) =>
      _matchesAny(_periodCache, after, replyLanguage);

  static bool hasAllowedActionUnitAfter(String after, String replyLanguage) =>
      _matchesAny(_actionCache, after, replyLanguage);

  static String? findForbiddenVitalUnitAfter(String after) =>
      _forbiddenVitalUnit.firstMatch(after)?.group(1);

  static bool containsUrlOrMarkdownLink(String text) =>
      _urlOrLink.hasMatch(text);

  static List<String> _localesFor(String lang) {
    final base = baseLocale(lang);
    return base == 'en' ? const ['en'] : [base, 'en'];
  }

  static bool _matchesAny(
    Map<String, RegExp> cache,
    String after,
    String lang,
  ) {
    for (final loc in _localesFor(lang)) {
      if (cache[loc]?.hasMatch(after) ?? false) return true;
    }
    return false;
  }

  static Map<String, RegExp> _unitCache(Map<String, String> patterns) => {
    for (final e in patterns.entries)
      e.key: RegExp(
        '^\\s*(?:${e.value})${_cjkLocales.contains(e.key) ? '' : '(?![$_alpha])'}',
        caseSensitive: false,
        unicode: true,
      ),
  };

  static Map<String, RegExp> _cache(Map<String, String> patterns) => {
    for (final e in patterns.entries)
      e.key: RegExp(_causalPattern(e.key, e.value), unicode: true),
  };

  static String _causalPattern(String locale, String value) {
    final alts = value.split('|').map(RegExp.escape).join('|');
    return _cjkLocales.contains(locale)
        ? '(?:$alts)'
        : '(?<![$_alpha])(?:$alts)(?![$_alpha])';
  }
}
