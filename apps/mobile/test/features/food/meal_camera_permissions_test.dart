import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _forbidden = [
  'android.permission.CAMERA',
  'android.permission.READ_MEDIA_IMAGES',
  'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.READ_MEDIA_VIDEO',
  'android.permission.READ_MEDIA_AUDIO',
  'android.permission.ACCESS_MEDIA_LOCATION',
  'android.permission.WRITE_EXTERNAL_STORAGE',
  'android.permission.MANAGE_EXTERNAL_STORAGE',
];

const _appManifests = [
  'android/app/src/main/AndroidManifest.xml',
  'android/app/src/debug/AndroidManifest.xml',
  'android/app/src/profile/AndroidManifest.xml',
];

File _packageConfig() {
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (config.existsSync()) return config;
    if (dir.parent.path == dir.path) {
      throw StateError('no .dart_tool/package_config.json above the test');
    }
  }
}

Map<String, File> _pluginManifests() {
  final config = _packageConfig();
  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final manifests = <String, File>{};
  for (final package in json['packages'] as List<dynamic>) {
    final entry = package as Map<String, dynamic>;
    final root = config.uri.resolve(entry['rootUri'] as String);
    final rootPath = root.toFilePath().replaceAll(RegExp(r'/$'), '');
    final manifest = File('$rootPath/android/src/main/AndroidManifest.xml');
    if (!manifest.existsSync()) continue;
    manifests[entry['name'] as String] = manifest;
  }
  return manifests;
}

String? _attribute(XmlElement element, String local) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == local) return attribute.value;
  }
  return null;
}

// A tools:node="remove" entry takes a permission out of the merged manifest.
List<String> _declared(File manifest) => [
  for (final element in XmlDocument.parse(
    manifest.readAsStringSync(),
  ).descendantElements)
    if (element.name.local.startsWith('uses-permission') &&
        _attribute(element, 'node') != 'remove')
      ?_attribute(element, 'name'),
];

void main() {
  group('criterion 8: no camera or media permission is declared', () {
    final plugins = _pluginManifests();

    test('the scan reaches the image picker plugin manifest', () {
      expect(plugins.keys, contains('image_picker_android'));
    });

    for (final path in _appManifests) {
      test('app manifest $path', () {
        expect(_declared(File(path)), isNot(anyElement(isIn(_forbidden))));
      });
    }

    for (final MapEntry(key: name, value: manifest) in plugins.entries) {
      test('plugin manifest of $name', () {
        expect(_declared(manifest), isNot(anyElement(isIn(_forbidden))));
      });
    }
  });

  group('D7: the Android build checks the merged manifest', () {
    test('android.yml names every forbidden permission', () {
      final workflow = File('../../.github/workflows/android.yml')
          .readAsStringSync();

      for (final permission in _forbidden) {
        final short = permission.split('.').last;

        expect(workflow, contains(short), reason: '$short is not checked');
      }
    });
  });
}
