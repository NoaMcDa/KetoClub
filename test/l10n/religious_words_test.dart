// Kosher and halal are flagged as components, never claimed (issue #342;
// file 03, "Kosher, halal, Jain"; file 10's non-goals): no menu text can
// show that a dish, its meat or its kitchen is kosher or halal. So no
// interface string says "kosher", "halal", "כשר" or "חלאל" except the one
// attributed statement ALG-09 already makes, "Declared kosher by the
// platform"; the restriction's own name, the chef card's self-description
// and its certificate question live in Dart and are pinned by
// `profile_evaluator_religious_test.dart`.
//
// The test reads both ARB files from disk as JSON, so a word cannot hide in
// a string the widget tests never render.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// The words that would read as a certification.
const _words = <String>['kosher', 'halal', 'כשר', 'חלאל'];

/// The keys allowed to say one: the platform's attributed kosher flag.
const _allowed = <String>{'dishCardDeclaredKosher'};

Map<String, Object?> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

void main() {
  for (final path in <String>['lib/l10n/app_en.arb', 'lib/l10n/app_he.arb']) {
    test('$path says kosher or halal only where the platform said it', () {
      final offending = <String>[];
      for (final MapEntry(:key, :value) in _arb(path).entries) {
        if (key.startsWith('@') || value is! String) continue;
        if (_allowed.contains(key)) continue;
        final lower = value.toLowerCase();
        if (_words.any(lower.contains)) offending.add('$key: $value');
      }
      expect(offending, isEmpty);
    });
  }

  test('the allowed key still exists and is attributed to the platform', () {
    final en = _arb('lib/l10n/app_en.arb')['dishCardDeclaredKosher']! as String;
    expect(en.toLowerCase(), contains('platform'));
  });

  test('the restriction names and the certificate question are the only '
      'Dart sentences that name them, by design', () {
    expect(restrictionFor(RestrictionId.kosher).nameEn, 'Kosher');
    expect(restrictionFor(RestrictionId.halal).nameEn, 'Halal');
    for (final hebrew in <bool>[false, true]) {
      // The question asks; it never answers.
      for (final id in <RestrictionId>[
        RestrictionId.kosher,
        RestrictionId.halal,
      ]) {
        expect(
          ChefCardText.certificationQuestion(id, hebrew: hebrew),
          endsWith('?'),
        );
      }
    }
  });
}
