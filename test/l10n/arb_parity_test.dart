// The two ARB files must stay in step: every string the UI can show exists in
// both languages, with the same placeholders (architecture.md §12, §18.6).
//
// This is a file-level test rather than a generated-code test on purpose: a key
// added to app_en.arb and forgotten in app_he.arb still compiles, and a Hebrew
// user would see English. The build cannot catch that; this test does.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads an ARB file and returns its message keys mapped to the sorted
/// placeholder names used inside the message value.
///
/// The names are a sorted list rather than a `Set` on purpose: two `Set`s with
/// equal contents are not `==` in Dart, so a set-valued comparison below would
/// report every message as mismatched.
Map<String, List<String>> _messages(String path) {
  final raw = File(path).readAsStringSync();
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?>) {
    fail('$path does not contain a JSON object');
  }
  final placeholder = RegExp(r'\{(\w+)\}');
  final messages = <String, List<String>>{};
  for (final entry in decoded.entries) {
    if (entry.key.startsWith('@')) continue;
    final value = entry.value;
    if (value is! String) fail('$path: ${entry.key} is not a string');
    final names =
        placeholder.allMatches(value).map((m) => m.group(1)!).toSet().toList()
          ..sort();
    messages[entry.key] = names;
  }
  return messages;
}

void main() {
  group('ARB files', () {
    late Map<String, List<String>> english;
    late Map<String, List<String>> hebrew;

    setUp(() {
      english = _messages('lib/l10n/app_en.arb');
      hebrew = _messages('lib/l10n/app_he.arb');
    });

    test('app_en.arb is not empty', () {
      // Assert: a mis-set path would otherwise make every check below pass.
      expect(english, isNotEmpty);
    });

    test('app_he.arb defines exactly the keys app_en.arb defines', () {
      // Act
      final missing = english.keys.toSet().difference(hebrew.keys.toSet());
      final extra = hebrew.keys.toSet().difference(english.keys.toSet());

      // Assert
      expect(missing, isEmpty, reason: 'untranslated keys');
      expect(extra, isEmpty, reason: 'keys with no English original');
    });

    test('every message uses the same placeholders in both languages', () {
      // Act
      final mismatched = <String>[];
      for (final entry in english.entries) {
        final translated = hebrew[entry.key];
        if (translated != null &&
            translated.join(',') != entry.value.join(',')) {
          mismatched.add('${entry.key}: en=${entry.value} he=$translated');
        }
      }

      // Assert
      expect(mismatched, isEmpty);
    });

    test('no message is left as an empty string', () {
      // Arrange
      final files = {
        'lib/l10n/app_en.arb': english,
        'lib/l10n/app_he.arb': hebrew,
      };

      // Assert
      for (final file in files.entries) {
        for (final key in file.value.keys) {
          final raw = jsonDecode(File(file.key).readAsStringSync());
          expect(
            (raw as Map<String, Object?>)[key],
            isNotEmpty,
            reason: '${file.key}: $key is empty',
          );
        }
      }
    });
  });
}
