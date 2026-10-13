// Banto is a helper tool, not a medical product (owner's decision; see
// docs/TERMS_NOTES.md). No user-facing string, in either language, may
// diagnose, treat, cure or promise: the store listings and the terms of use
// say "helper tool", and the copy has to say the same.
//
// The test reads both ARB files from disk as JSON, so a banned word cannot
// hide in a string the widget tests never render.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// English fragments that may not appear in any value.
///
/// Each is matched case-insensitively and only at the start of a word (not
/// preceded by a letter), so `secure` and `retreat` do not trip `cure` and
/// `treat`, while `cure`, `cured`, `treatment` and `Treats` do.
const _bannedEnglish = <String>[
  'diagnos',
  'treat',
  'cure',
  'medical device',
  'medically',
  'guarantee',
  '100%',
];

/// Hebrew fragments that may not appear in any value.
///
/// Matched as plain substrings: Dart's `\b` is ASCII-only, so a word-boundary
/// pattern would silently match nothing here.
const _bannedHebrew = <String>[
  'מאבחן',
  'אבחון',
  'מטפל',
  'טיפול רפואי',
  'מכשיר רפואי',
  'מבטיח',
];

/// Keys whose value may contain a banned word, with the reason.
///
/// Keyed by the word it is allowed to contain, so an exemption never widens
/// to the other banned words.
const _allowed = <String, Map<String, String>>{
  'guarantee': {
    'helperToolTitle':
        '"A helper, not a guarantee": the point is to disclaim a guarantee.',
  },
  'treat': {
    'settingsDairyFreeHint':
        '"Treats cream ... as a modification": "treat" as a verb for how the '
        'rule engine handles an ingredient, not a medical claim.',
  },
  'מבטיח': {
    'helperToolSentence':
        '"לא מבטיחה דיוק" (does not promise accuracy): the sentence '
        'disclaims a promise, and the owner fixed this wording.',
  },
};

/// The Banto keys this change adds; they must exist, non-empty, in both files.
const _bantoKeys = <String>[
  'helperToolSentence',
  'helperToolTitle',
  'whatLeavesDeviceBanto',
];

Map<String, String> _values(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    fail('$path does not contain a JSON object');
  }
  return {
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value! as String,
  };
}

bool _containsEnglish(String value, String banned) {
  final pattern = RegExp(
    '(?<![A-Za-z])${RegExp.escape(banned)}',
    caseSensitive: false,
  );
  return pattern.hasMatch(value);
}

void main() {
  const files = {
    'app_en.arb': 'lib/l10n/app_en.arb',
    'app_he.arb': 'lib/l10n/app_he.arb',
  };

  for (final file in files.entries) {
    group(file.key, () {
      late Map<String, String> values;

      setUp(() => values = _values(file.value));

      test('has values to check', () {
        // Assert: a mis-set path would otherwise make the ban pass vacuously.
        expect(values, isNotEmpty);
      });

      test('no value contains a banned word', () {
        // Arrange
        final violations = <String>[];

        // Act
        for (final entry in values.entries) {
          for (final banned in _bannedEnglish) {
            if (_allowed[banned]?.containsKey(entry.key) ?? false) continue;
            if (_containsEnglish(entry.value, banned)) {
              violations.add('${entry.key} contains "$banned"');
            }
          }
          for (final banned in _bannedHebrew) {
            if (_allowed[banned]?.containsKey(entry.key) ?? false) continue;
            if (entry.value.contains(banned)) {
              violations.add('${entry.key} contains "$banned"');
            }
          }
        }

        // Assert
        expect(violations, isEmpty, reason: violations.join('\n'));
      });

      test('has the helper-tool keys, non-empty', () {
        for (final key in _bantoKeys) {
          expect(values[key], isNotNull, reason: '$key is missing');
          expect(values[key]!.trim(), isNotEmpty, reason: '$key is empty');
        }
      });
    });
  }

  test('the exemptions are exactly the three reviewed ones', () {
    // Assert: the allowlist must not grow quietly.
    expect(
      {
        for (final word in _allowed.entries)
          for (final key in word.value.keys) '${word.key}:$key',
      },
      {
        'guarantee:helperToolTitle',
        'treat:settingsDairyFreeHint',
        'מבטיח:helperToolSentence',
      },
    );
  });
}
