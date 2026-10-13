// Architecture test: the restriction profile never leaves the device
// (Banto contract decision C1; architecture.md §11, "Banto (C1)").
//
// Everything that talks to the network, the platform or storage lives under
// lib/services/. If no file there can even name a restriction id, a dietary
// profile, a profile entry or a severity, then no service can put them in a
// request, a log line or a cache row. This is the mechanical form of "the
// profile never leaves the device, not even as ids": the tokens simply do not
// exist on the service side of the wire. The backend half is
// backend/tests/test_menus_profile_rejected.py, which makes the shared menu
// store refuse a body that carries a profile.
//
// A legitimate future exception must be an explicit entry in [_allowed], with
// the file, the token and the reason. Never loosen [_tokens] instead.
//
// The one such exception so far is settings_store.dart (ALG-02a, #344):
// storage on the device is where C1 says the profile lives, and the file
// writes only to shared_preferences. Every other service — the HTTP
// clients, the classifiers, the logger — still cannot name it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Identifiers (and one word) that name the restriction profile.
///
/// Matched case-sensitively as plain substrings, so `restrictionIds` and
/// `userDietaryProfile` are caught as well.
const _tokens = <String>[
  'restrictionId',
  'RestrictionId',
  'dietaryProfile',
  'DietaryProfile',
  'profileEntries',
  'severity',
];

/// Lib-relative file -> token -> why that file may contain it.
const _allowed = <String, Map<String, String>>{
  'services/platform/app_logger.dart': {
    'severity':
        'Two doc comments describe a log level as its "severity"; the file '
        'has no profile data and no code mentions the word.',
  },
  'services/storage/settings_store.dart': {
    'DietaryProfile':
        'AppSettings holds the profile so it is stored on the device '
        '(ALG-02a, issue #344). The file only reads and writes '
        'shared_preferences; it builds no request body and logs nothing, '
        'and AppSettings.toString prints a count, never the restrictions.',
    'dietaryProfile':
        'The shared_preferences JSON key the profile is stored under, '
        'written only when the profile is non-empty (ALG-02a). On-device '
        'storage, the place C1 says the profile lives.',
  },
};

void main() {
  test('no file under lib/services/ names the restriction profile', () {
    final services = Directory('lib/services');
    final violations = <String>[];
    var scanned = 0;

    for (final entity in services.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      scanned++;
      final relative = entity.path.replaceAll(r'\', '/').split('lib/').last;
      final allowedHere = _allowed[relative] ?? const <String, String>{};

      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final token in _tokens) {
          if (allowedHere.containsKey(token)) continue;
          if (lines[i].contains(token)) {
            violations.add('lib/$relative:${i + 1}: "$token"');
          }
        }
      }
    }

    expect(scanned, greaterThan(0), reason: 'lib/services/ was not scanned');
    expect(
      violations,
      isEmpty,
      reason:
          'The restriction profile stays on the device (Banto C1). A service '
          'must not name it:\n${violations.join('\n')}',
    );
  });

  test('every allowlisted file exists and still needs its exemption', () {
    // Assert: a stale entry would otherwise widen the net silently.
    for (final file in _allowed.entries) {
      final source = File('lib/${file.key}');
      expect(source.existsSync(), isTrue, reason: '${file.key} is gone');
      final text = source.readAsStringSync();
      for (final token in file.value.keys) {
        expect(
          text.contains(token),
          isTrue,
          reason: '${file.key} no longer contains "$token"; drop the entry',
        );
      }
    }
  });
}
