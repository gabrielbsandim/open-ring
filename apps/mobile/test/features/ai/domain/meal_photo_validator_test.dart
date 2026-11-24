import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/ai/domain/meal_photo_validator.dart';

Map<String, Object?> _tags({
  String isFood = 'yes',
  String kind = 'main',
  String protein = 'yes',
  String caffeine = 'no',
  String fried = 'no',
  String sugaryDrink = 'no',
  String veg = 'some',
  String alcohol = 'none',
  String processed = 'not_mostly',
  String confidence = 'high',
}) => {
  'is_food': isFood,
  'kind': kind,
  'protein': protein,
  'caffeine': caffeine,
  'fried': fried,
  'sugary_drink': sugaryDrink,
  'veg': veg,
  'alcohol': alcohol,
  'processed': processed,
  'confidence': confidence,
};

Map<String, Object?> _item(
  String name, {
  String measure = 'serving_spoon',
  Object count = 2,
  Object grams = 100,
}) => {'name': name, 'measure': measure, 'count': count, 'grams': grams};

MealPhotoOutcome _read(
  Object answer, {
  bool withItems = false,
  int shortEdgePx = 768,
  String lang = 'en',
}) => MealPhotoValidator.read(
  answer is String ? answer : jsonEncode(answer),
  shortEdgePx: shortEdgePx,
  withItems: withItems,
  replyLanguage: lang,
);

MealPhotoDone _done(
  Object answer, {
  bool withItems = false,
  int shortEdgePx = 768,
  String lang = 'en',
}) {
  final outcome = _read(
    answer,
    withItems: withItems,
    shortEdgePx: shortEdgePx,
    lang: lang,
  );
  expect(outcome, isA<MealPhotoDone>());
  return outcome as MealPhotoDone;
}

MealPhotoDone _withItems(
  List<Map<String, Object?>> items, {
  String lang = 'en',
}) => _done({..._tags(), 'items': items}, withItems: true, lang: lang);

MealPhotoRejectReason? _reason(MealPhotoOutcome outcome) =>
    outcome is MealPhotoRejected ? outcome.reason : null;

void main() {
  group('acceptance 3: fixtures', () {
    test('a valid answer is done with the tags as suggestions', () {
      final done = _done(_tags());
      final s = done.suggestion;
      expect(s.isFood, MealPhotoFlag.yes);
      expect(s.kind, MealPhotoKind.main);
      expect(s.protein, MealPhotoFlag.yes);
      expect(s.veg, MealPhotoVeg.some);
      expect(s.alcohol, MealPhotoAlcohol.none);
      expect(s.processed, MealPhotoProcessed.notMostly);
      expect(s.items, isEmpty);
      expect(done.droppedItems, 0);
    });

    test('is_food no is not food and nothing else is read', () {
      expect(_read({'is_food': 'no'}), isA<MealPhotoNotFood>());
      expect(
        _read({..._tags(isFood: 'no', kind: 'bogus'), 'extra': 1}),
        isA<MealPhotoNotFood>(),
      );
    });

    test('is_food unsure keeps tags, drops items, confidence low', () {
      final done = _done({
        ..._tags(isFood: 'unsure'),
        'items': [_item('rice'), _item('beans')],
      }, withItems: true);
      expect(done.suggestion.isFood, MealPhotoFlag.unsure);
      expect(done.suggestion.kind, MealPhotoKind.main);
      expect(done.suggestion.items, isEmpty);
      expect(done.droppedItems, 2);
      expect(done.confidence, MealPhotoConfidence.low);
    });

    test('is_food unsure with no signal is still done', () {
      final done = _done(
        _tags(
          isFood: 'unsure',
          kind: 'unsure',
          protein: 'unsure',
          caffeine: 'unsure',
          fried: 'unsure',
          sugaryDrink: 'unsure',
          veg: 'unsure',
          processed: 'unsure',
        ),
      );
      expect(done.confidence, MealPhotoConfidence.low);
    });

    final offSchema = <String, Map<String, Object?>>{
      'unknown enum': _tags(kind: 'dessert'),
      'unknown is_food': _tags(isFood: 'maybe'),
      'unknown confidence': _tags(confidence: 'certain'),
      'wrong type': {..._tags(), 'protein': true},
      'extra key': {..._tags(), 'heavy': 'yes'},
      'missing key': {..._tags()}..remove('veg'),
      'items without withItems': {..._tags(), 'items': <Object?>[]},
    };
    for (final MapEntry(:key, :value) in offSchema.entries) {
      test('$key is rejected', () {
        expect(_reason(_read(value)), MealPhotoRejectReason.offSchema);
      });
    }

    final itemOffSchema = <String, Object?>{
      'items missing': null,
      'items not a list': 'rice',
      'item not an object': ['rice'],
      'item unknown measure': [_item('rice', measure: 'plate')],
      'item string grams': [_item('rice', grams: '100')],
      'item fractional grams': [_item('rice', grams: 100.5)],
      'item string count': [_item('rice', count: 'two')],
      'item extra key': [
        {..._item('rice'), 'kcal': 200},
      ],
      'item missing key': [
        {..._item('rice')}..remove('grams'),
      ],
      'item name not a string': [_item('rice')..['name'] = 3],
    };
    for (final MapEntry(:key, :value) in itemOffSchema.entries) {
      test('$key is rejected', () {
        final answer = {..._tags(), 'items': ?value};
        expect(
          _reason(_read(answer, withItems: true)),
          MealPhotoRejectReason.offSchema,
        );
      });
    }

    test('think blocks and fences are stripped', () {
      final json = jsonEncode(_tags());
      expect(
        _read('<think>{"is_food":"no"}</think>\n$json'),
        isA<MealPhotoDone>(),
      );
      expect(_read('```json\n$json\n```'), isA<MealPhotoDone>());
      expect(
        _read('Here you go:\n```\n$json\n```\nDone.'),
        isA<MealPhotoDone>(),
      );
    });

    test('text without a JSON object is rejected as not json', () {
      expect(_reason(_read('I see rice.')), MealPhotoRejectReason.notJson);
      expect(_reason(_read('{"is_food": ')), MealPhotoRejectReason.notJson);
      expect(_reason(_read('[1, 2]')), MealPhotoRejectReason.notJson);
    });

    test('an oversized answer is rejected as not json', () {
      final big = '${jsonEncode(_tags())}${' ' * (256 * 1024)}';
      expect(_reason(_read(big)), MealPhotoRejectReason.notJson);
    });

    test('yes with every tag unsure or none and no items is rejected', () {
      final answer = _tags(
        kind: 'unsure',
        protein: 'unsure',
        caffeine: 'unsure',
        fried: 'unsure',
        sugaryDrink: 'unsure',
        veg: 'none',
        processed: 'unsure',
      );
      expect(_reason(_read(answer)), MealPhotoRejectReason.noSignal);
      expect(
        _reason(_read({...answer, 'items': <Object?>[]}, withItems: true)),
        MealPhotoRejectReason.noSignal,
      );
      expect(
        _read({
          ...answer,
          'items': [_item('rice')],
        }, withItems: true),
        isA<MealPhotoDone>(),
      );
      expect(_read({...answer, 'protein': 'no'}), isA<MealPhotoDone>());
    });
  });

  group('acceptance 4: items', () {
    test('valid items are kept with count in halves', () {
      final done = _withItems([
        _item('Rice', count: 1.5, grams: 150),
        _item('Feijão', measure: 'ladle', count: 1, grams: 140),
      ]);
      expect(done.suggestion.items, const [
        MealPhotoItem(
          name: 'Rice',
          measure: MealPhotoMeasure.servingSpoon,
          countX2: 3,
          grams: 150,
        ),
        MealPhotoItem(
          name: 'Feijão',
          measure: MealPhotoMeasure.ladle,
          countX2: 2,
          grams: 140,
        ),
      ]);
      expect(done.droppedItems, 0);
      expect(done.confidence, MealPhotoConfidence.medium);
    });

    test('at most 8 items are kept', () {
      const names = [
        'apple',
        'bread',
        'carrot',
        'dates',
        'egg',
        'fig',
        'grape',
        'ham',
        'kiwi',
        'lime',
      ];
      final done = _withItems([for (final n in names) _item(n, grams: 50)]);
      expect(done.suggestion.items.map((i) => i.name), names.take(8));
      expect(done.droppedItems, 2);
    });

    test('duplicates by case folded name and measure merge', () {
      final done = _withItems([
        _item('Rice', count: 1),
        _item('bread', count: 1, grams: 50),
        _item(' rice ', count: 0.5, grams: 80),
        _item('ÄPFEL', count: 1, grams: 90),
        _item('äpfel', count: 1, grams: 90),
      ]);
      expect(done.suggestion.items, const [
        MealPhotoItem(
          name: 'Rice',
          measure: MealPhotoMeasure.servingSpoon,
          countX2: 3,
          grams: 180,
        ),
        MealPhotoItem(
          name: 'bread',
          measure: MealPhotoMeasure.servingSpoon,
          countX2: 2,
          grams: 50,
        ),
        MealPhotoItem(
          name: 'ÄPFEL',
          measure: MealPhotoMeasure.servingSpoon,
          countX2: 4,
          grams: 180,
        ),
      ]);
      expect(done.droppedItems, 0);
    });

    test('the same name with another measure stays a separate item', () {
      final done = _withItems([
        _item('rice', measure: 'cup', grams: 150),
        _item('Rice', measure: 'bowl', grams: 200),
      ]);
      expect(done.suggestion.items.map((i) => i.measure), [
        MealPhotoMeasure.cup,
        MealPhotoMeasure.bowl,
      ]);
      expect(done.droppedItems, 0);
    });

    test('separate measures still count toward the cap of 8', () {
      final done = _withItems([
        for (final m in ['unit', 'slice', 'cup', 'glass', 'bowl'])
          _item('rice', measure: m, grams: 50),
        for (final m in ['unit', 'slice', 'cup', 'glass', 'bowl'])
          _item('bread', measure: m, grams: 50),
      ]);
      expect(done.suggestion.items, hasLength(8));
      expect(done.droppedItems, 2);
    });

    test('a merged item past 1500 g is dropped and lowers confidence', () {
      final done = _withItems([
        _item('rice', grams: 1400, count: 6),
        _item('Rice', grams: 1000, count: 6),
        _item('beans', grams: 50),
      ]);
      expect(done.suggestion.items.map((i) => i.name), ['beans']);
      expect(done.droppedItems, 1);
      expect(done.confidence, MealPhotoConfidence.low);
    });

    test(
      'a merged item past a count of 6 is dropped and lowers confidence',
      () {
        final done = _withItems([
          _item('egg', measure: 'unit', count: 4, grams: 200),
          _item('Egg', measure: 'unit', count: 3, grams: 150),
          _item('beans', grams: 50),
        ]);
        expect(done.suggestion.items.map((i) => i.name), ['beans']);
        expect(done.droppedItems, 1);
        expect(done.confidence, MealPhotoConfidence.low);
      },
    );

    group('name sanitizer', () {
      const lookalikeSafe = [
        'ph\u1edf b\u00f2',
        'b\u00e1nh m\u00ec',
        '\u0926\u093e\u0932 \u092e\u0916\u0928\u0940',
        '\u30e9\u30fc\u30e1\u30f3',
        '\u03c3\u03bf\u03c5\u03b2\u03bb\u03ac\u03ba\u03b9',
        '\u0e02\u0e49\u0e32\u0e27\u0e1c\u0e31\u0e14',
        '\uae40\uce58\ucc0c\uac1c',
        '\u0643\u064f\u0633\u0652\u0643\u064f\u0633',
        "p\u00e3o d'\u00e1gua",
        'p\u00e9-de-moleque',
      ];
      for (final name in lookalikeSafe) {
        test('keeps "$name"', () {
          expect(MealPhotoValidator.isCleanItemName(name, 'en'), isTrue);
        });
      }

      const clean = <String, String>{
        'en': 'grilled chicken',
        'pt-BR': 'pão de queijo',
        'es': 'jalapeño',
        'fr': 'crème brûlée',
        'de': 'Käsespätzle',
        'ru': 'гречка с грибами',
        'uk': 'борщ',
        'ja': 'ご飯',
        'zh': '红烧肉',
        'ko': '김치찌개',
        'hi': 'दाल',
      };
      for (final MapEntry(:key, :value) in clean.entries) {
        test('keeps "$value" ($key)', () {
          expect(MealPhotoValidator.isCleanItemName(value, key), isTrue);
          final done = _withItems([_item(value)], lang: key);
          expect(done.suggestion.items.single.name, value);
        });
      }

      test('keeps hyphens, apostrophes and precomposed accents', () {
        expect(MealPhotoValidator.isCleanItemName("pick-n'-mix", 'en'), isTrue);
        expect(MealPhotoValidator.isCleanItemName('caf\u00e9', 'fr'), isTrue);
        expect(
          MealPhotoValidator.isCleanItemName('\u0130zmir k\u00f6fte', 'tr'),
          isTrue,
        );
      });

      const bypass = <String, (String, String)>{
        'grapheme joiner': ('insu\u034Flin', 'en'),
        'zero width joiner': ('insu\u200Dlin', 'en'),
        'word joiner': ('insu\u2060lin', 'en'),
        'byte order mark': ('insu\uFEFFlin', 'en'),
        'dotted capital I': ('\u0130nsulin', 'en'),
        'decomposed i dot': ('i\u0307nsulin', 'en'),
        'NFD accent': ('farma\u0301cia', 'pt-BR'),
        'NFD accent, harmless word': ('cafe\u0301', 'fr'),
        'Cyrillic homoglyph': ('\u0456nsulin', 'en'),
        'Greek homoglyph': ('insul\u03b9n', 'en'),
        'mark after a space': ('\u0926\u093E\u0932 \u093E', 'hi'),
        'Cyrillic variation selector': (
          '\u0438\u043d\u0441\u0443\uFE0F\u043b\u0438\u043d',
          'ru',
        ),
        'CJK variation selector': ('\u80f0\uFE0F\u5c9b\u7d20', 'zh'),
        'ideographic variation selector': ('\u80f0\u{E0100}\u5c9b\u7d20', 'zh'),
        'dotless i': ('\u0131nsul\u0131na', 'pt-BR'),
        'fullwidth': (
          '\uFF49\uFF4E\uFF53\uFF55\uFF4C\uFF49\uFF4E\uFF41',
          'pt-BR',
        ),
        'small caps': ('\u026A\u0274s\u1D1C\u029F\u026A\u0274\u1D00', 'pt-BR'),
        'long s': ('in\u017Fulina', 'pt-BR'),
        'math bold': (
          '\u{1D422}\u{1D427}\u{1D42C}\u{1D42E}\u{1D425}\u{1D422}\u{1D427}\u{1D41A}',
          'pt-BR',
        ),
        'Armenian homoglyph': ('d\u0585se', 'en'),
      };
      for (final MapEntry(:key, value: (name, lang)) in bypass.entries) {
        test('rejects the $key bypass', () {
          expect(MealPhotoValidator.isCleanItemName(name, lang), isFalse);
          final done = _withItems([_item(name), _item('rice')], lang: lang);
          expect(done.suggestion.items.map((i) => i.name), ['rice']);
        });
      }

      test('a pt only stem is dropped in pt-BR and kept in en', () {
        const name = 'rem\u00e9dio caseiro';
        expect(MealPhotoValidator.isCleanItemName(name, 'pt-BR'), isFalse);
        expect(MealPhotoValidator.isCleanItemName(name, 'en'), isTrue);
      });

      const dirty = <String, String>{
        'empty': '',
        'leading space only': ' ',
        'starts with a mark': '́cafe',
        'starts with a hyphen': '-rice',
        'ASCII digit': 'rice 2',
        'Arabic Indic digit': 'أرز٢',
        'full width digit': '米饭２',
        'CJK numeral sign': '米饭。',
        'Cyrillic with digit': 'гречка1',
        'URL': 'https://x.co',
        'domain': 'rice.com',
        'markdown link': '[rice](x)',
        'newline': 'rice\nbeans',
        'emoji': 'rice 🍚',
        'too long': 'a very long name for a simple bowl of rice',
        'medical en': 'insulin',
        'medical pt': 'pão para diabetes',
      };
      for (final MapEntry(:key, :value) in dirty.entries) {
        test('drops $key alone', () {
          final lang = key.endsWith(' pt') ? 'pt-BR' : 'en';
          final done = _withItems([_item(value), _item('rice')], lang: lang);
          expect(done.suggestion.items.map((i) => i.name), ['rice']);
          expect(done.droppedItems, 1);
          expect(done.confidence, MealPhotoConfidence.medium);
        });
      }

      test('32 letters are allowed and 33 are not', () {
        expect(MealPhotoValidator.isCleanItemName('a' * 32, 'en'), isTrue);
        expect(MealPhotoValidator.isCleanItemName('a' * 33, 'en'), isFalse);
        expect(MealPhotoValidator.isCleanItemName('饭' * 32, 'zh'), isTrue);
      });
    });

    final implausible = <String, Map<String, Object?>>{
      'zero grams': _item('rice', grams: 0),
      'negative grams': _item('rice', grams: -5),
      'grams above 1500': _item('rice', grams: 1501),
      'count below a half': _item('rice', count: 0),
      'count above 6': _item('rice', count: 6.5),
      'count not a half': _item('rice', count: 1.25),
    };
    for (final MapEntry(:key, :value) in implausible.entries) {
      test('$key drops that item and lowers confidence', () {
        final done = _withItems([value, _item('beans')]);
        expect(done.suggestion.items.map((i) => i.name), ['beans']);
        expect(done.droppedItems, 1);
        expect(done.confidence, MealPhotoConfidence.low);
      });
    }

    test('grams 1 and 1500 and counts 0.5 and 6 are kept', () {
      final done = _withItems([
        _item('salt', count: 0.5, grams: 1),
        _item('soup', count: 6, grams: 1500),
      ]);
      expect(done.suggestion.items, hasLength(2));
      expect(done.confidence, MealPhotoConfidence.medium);
    });

    test('a total of exactly 2500 g is kept', () {
      final done = _withItems([
        _item('rice', grams: 1500),
        _item('beans', grams: 1000),
      ]);
      expect(done.suggestion.items, hasLength(2));
      expect(done.confidence, MealPhotoConfidence.medium);
    });

    test('a total above 2500 g drops every item and sets low', () {
      final done = _withItems([
        _item('rice', grams: 1500),
        _item('beans', grams: 1000),
        _item('salad', grams: 1),
      ]);
      expect(done.suggestion.items, isEmpty);
      expect(done.droppedItems, 3);
      expect(done.confidence, MealPhotoConfidence.low);
      expect(done.suggestion.kind, MealPhotoKind.main);
    });

    test('merged duplicates count toward the 2500 g total', () {
      final done = _withItems([
        _item('rice', grams: 1300),
        _item('Rice', grams: 1300),
      ]);
      expect(done.suggestion.items, isEmpty);
      expect(done.droppedItems, 1);
      expect(done.confidence, MealPhotoConfidence.low);
    });
  });

  group('acceptance 5: confidence', () {
    test('high is capped at medium', () {
      expect(_done(_tags()).confidence, MealPhotoConfidence.medium);
    });

    test('medium and low pass through', () {
      expect(
        _done(_tags(confidence: 'medium')).confidence,
        MealPhotoConfidence.medium,
      );
      expect(
        _done(_tags(confidence: 'low')).confidence,
        MealPhotoConfidence.low,
      );
    });

    test('any unsure tag makes it low', () {
      expect(
        _done(_tags(caffeine: 'unsure')).confidence,
        MealPhotoConfidence.low,
      );
      expect(_done(_tags(veg: 'unsure')).confidence, MealPhotoConfidence.low);
    });

    test('a short edge under 400 px makes it low', () {
      expect(
        _done(_tags(), shortEdgePx: 399).confidence,
        MealPhotoConfidence.low,
      );
      expect(
        _done(_tags(), shortEdgePx: 400).confidence,
        MealPhotoConfidence.medium,
      );
    });
  });

  group('acceptance 6: result_json', () {
    test('a suggestion survives a round trip unchanged', () {
      final done = _withItems([
        _item('Rice', count: 1.5, grams: 150),
        _item('гречка', measure: 'bowl', grams: 200),
        _item('红烧肉', measure: 'tongs', count: 3, grams: 120),
      ]);
      final json = jsonEncode(done.suggestion.toJson());
      final back = MealPhotoSuggestion.fromJson(
        jsonDecode(json) as Map<String, Object?>,
      );
      expect(back!.items, done.suggestion.items);
      expect(jsonEncode(back.toJson()), json);
    });

    test('a tags only suggestion round trips with an empty list', () {
      final s = _done(_tags(isFood: 'unsure')).suggestion;
      final json = s.toJson();
      expect(json['items'], isEmpty);
      expect(MealPhotoSuggestion.fromJson(json)!.toJson(), json);
    });

    test('a corrupt stored value reads as null', () {
      final good = _done(_tags()).suggestion.toJson();
      expect(MealPhotoSuggestion.fromJson({...good, 'kind': 'x'}), isNull);
      expect(MealPhotoSuggestion.fromJson({...good, 'items': 'x'}), isNull);
      expect(
        MealPhotoSuggestion.fromJson({
          ...good,
          'items': [
            {'name': 'rice', 'measure': 'cup', 'count_x2': 1.5, 'grams': 1},
          ],
        }),
        isNull,
      );
    });

    test('wire names are snake case and read back', () {
      expect(mealWireName(MealPhotoMeasure.servingSpoon), 'serving_spoon');
      expect(mealWireName(MealPhotoAlcohol.threeOrMore), 'three_or_more');
      expect(
        mealEnumFromWire(MealPhotoVeg.values, 'half_or_more'),
        MealPhotoVeg.halfOrMore,
      );
      expect(mealEnumFromWire(MealPhotoVeg.values, 'halfOrMore'), isNull);
      expect(mealEnumFromWire(MealPhotoVeg.values, 3), isNull);
    });
  });
}
