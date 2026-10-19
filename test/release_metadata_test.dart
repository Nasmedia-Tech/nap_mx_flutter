import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _versionIn(String path, String pattern) {
  final match = RegExp(pattern, multiLine: true)
      .firstMatch(File(path).readAsStringSync());
  expect(match, isNotNull, reason: 'Missing version declaration in $path');
  return match!.group(1)!;
}

void main() {
  test('native runtime and CocoaPods versions match the package release', () {
    final version = _versionIn('pubspec.yaml', r'^version:\s*(\S+)');
    final declarations = <String, String>{
      'android/src/main/kotlin/com/nasmedia/nap_mx_flutter/NapMxFlutterPlugin.kt':
          r'const val PLUGIN_VERSION = "([^"]+)"',
      'ios/nap_mx_flutter/Sources/nap_mx_flutter/NapMxFlutterPlugin.swift':
          r'let pluginVersion = "([^"]+)"',
      'ios/nap_mx_flutter.podspec': r"s\.version\s*=\s*'([^']+)'",
    };

    for (final entry in declarations.entries) {
      expect(_versionIn(entry.key, entry.value), version,
          reason: '${entry.key} must report the pubspec.yaml release version');
    }
  });
}
