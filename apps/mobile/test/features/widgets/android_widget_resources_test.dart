import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/widgets/domain/widget_gateway.dart';
import 'package:xml/xml.dart';

const _res = 'android/app/src/main/res';

const _localeDirs = [
  'values-de',
  'values-es',
  'values-fr',
  'values-it',
  'values-ja',
  'values-pt',
  'values-pt-rPT',
  'values-ru',
  'values-zh',
  'values-in',
];

Map<String, String> _resources(String path, String tag) => {
  for (final element in XmlDocument.parse(
    File(path).readAsStringSync(),
  ).findAllElements(tag))
    element.getAttribute('name')!: element.innerText,
};

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

Map<String, Color Function(AppColors)> get _tokens => {
  'background': (c) => c.background,
  'surface': (c) => c.surface,
  'surface_border': (c) => c.surfaceBorder,
  'surface_inner': (c) => c.surfaceInner,
  'strong_border': (c) => c.strongBorder,
  'track': (c) => c.track,
  'nav_bar': (c) => c.navBar,
  'text_primary': (c) => c.textPrimary,
  'text_secondary': (c) => c.textSecondary,
  'text_label': (c) => c.textLabel,
  'sleep': (c) => c.sleep,
  'heart': (c) => c.heart,
  'activity': (c) => c.activity,
  'oxygen': (c) => c.oxygen,
  'stress': (c) => c.stress,
  'on_accent': (c) => c.onAccent,
};

void main() {
  test('widget colours mirror the design tokens in both modes', () {
    final day = _resources('$_res/values/widget_colors.xml', 'color');
    final night = _resources('$_res/values-night/widget_colors.xml', 'color');

    for (final MapEntry(key: name, value: token) in _tokens.entries) {
      expect(day['widget_dark_$name'], _hex(token(AppColors.dark)));
      expect(day['widget_light_$name'], _hex(token(AppColors.light)));
      expect(day['widget_$name'], '@color/widget_light_$name');
      expect(night['widget_$name'], '@color/widget_dark_$name');
    }
  });

  test('every locale translates every widget string', () {
    final english = _resources('$_res/values/strings.xml', 'string');

    for (final dir in _localeDirs) {
      final local = _resources('$_res/$dir/strings.xml', 'string');
      expect(local.keys.toSet(), english.keys.toSet(), reason: dir);
      for (final MapEntry(:key, :value) in english.entries) {
        final placeholders = RegExp(r'%\d\$[sd]');
        expect(
          placeholders.allMatches(local[key]!).map((m) => m[0]).toSet(),
          placeholders.allMatches(value).map((m) => m[0]).toSet(),
          reason: '$dir $key',
        );
      }
    }
  });

  test('every widget receiver is declared in the manifest', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    for (final kind in HomeWidgetKind.values) {
      expect(manifest, contains('android:name=".widget.${kind.receiver}"'));
      expect(
        File('$_res/xml/widget_${kind.name}_info.xml').existsSync(),
        isTrue,
      );
    }
  });
}
