// Banto is a helper tool, not a medical product (owner's decision; see
// docs/TERMS_NOTES.md). No user-facing string, in either language, may
// diagnose, treat, cure or promise: the store listings and the terms of use
// say "helper tool", and the copy has to say the same.
//
// The test reads both ARB files from disk as JSON, so a banned word cannot
// hide in a string the widget tests never render.
//
// The chef card (issue #419) is read by restaurant staff in Hebrew,
// English, French, Italian, Spanish, German or Japanese, so its sentences
// live in Dart; the last group composes every line of it, in every
// language, and bans a word meaning "safe" in each of them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/chef_card_locales.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

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

/// Words meaning "safe", per language, banned from every chef card line.
///
/// A Latin-script word is matched case-insensitively at the start of a
/// word (not preceded by a letter, Unicode-aware), so "sécurité",
/// "Sicherheit", "sicherstellen" and "seguridad" are caught with their
/// stems; Hebrew and Japanese are matched as substrings, since `\b` does
/// not see their letters.
const _safeWords = <String, List<String>>{
  'en': <String>['safe'],
  'he': <String>['בטוח'],
  'fr': <String>['sans danger', 'sûr', 'sécuri'],
  'it': <String>['sicur'],
  'es': <String>['segur'],
  'de': <String>['sicher'],
  'ja': <String>['安全'],
};

/// Every line the chef card can show in [language]: one card per
/// restriction (its line, its certification question, the closing), the
/// user's own words, an entry's exceptions, a dish card with and without
/// cross-contact, a group card for a dish, and the image footer.
List<String> _chefCardLines(ChefCardLanguage language) {
  final hebrew = language == ChefCardLanguage.he;
  final lines = <String>[
    for (final restriction in restrictionTaxonomy)
      ...ChefCardText.compose(
        DietaryProfile.empty.withEntry(
          restriction.id,
          exceptions: const <String>['x'],
          terms: restriction.id == RestrictionId.custom
              ? const <String>['kiwi']
              : null,
        ),
        hebrew: hebrew,
        language: language,
      ),
    for (final crossContact in <bool>[false, true])
      ...ChefCardText.composeForDish(
        DietaryProfile.empty.withEntry(RestrictionId.milk),
        dishName: 'Dish',
        modification: null,
        questions: const <String>[],
        crossContact: crossContact,
        hebrew: hebrew,
        language: language,
      ),
    ChefCardText.imageFooter(language),
  ];
  final group = GroupChefCardText.composeForDish(
    <PersonDishPart>[
      (
        person: const NamedProfile(id: 'me', name: ''),
        modification: null,
        questions: const <String>[],
      ),
    ],
    dishName: 'Dish',
    crossContact: true,
    hebrew: hebrew,
    language: language,
  );
  return <String>[
    ...lines,
    GroupChefCardText.asText(group),
    GroupChefCardText.asText(
      GroupChefCardText.compose(
        const <NamedProfile>[NamedProfile(id: 'me', name: '')],
        hebrew: hebrew,
        language: language,
      ),
    ),
  ];
}

/// Whether [line] holds [word]: at a word start for Latin script, as a
/// substring otherwise.
bool _holds(String line, String word) {
  if (RegExp('[A-Za-zÀ-ÿ]').hasMatch(word)) {
    return RegExp(
      '(?<!\\p{L})${RegExp.escape(word)}',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(line);
  }
  return line.contains(word);
}

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

  group('the chef card, in every language (#419)', () {
    test('the matcher catches each banned word and its stems', () {
      expect(_holds('Ce plat est sûr.', 'sûr'), isTrue);
      expect(_holds('Bitte sicherstellen', 'sicher'), isTrue);
      expect(_holds('Es seguro', 'segur'), isTrue);
      expect(_holds('è sicuro', 'sicur'), isTrue);
      expect(_holds('安全です', '安全'), isTrue);
      // Not at a word start: "assurer" holds no "sûr", "Unsafe" no "safe".
      expect(_holds('assurer', 'sûr'), isFalse);
      expect(_holds('asegurar', 'segur'), isFalse);
      expect(_holds('Unsafe', 'safe'), isFalse);
    });

    for (final language in ChefCardLanguage.values) {
      test('${language.name}: no line holds a word meaning "safe"', () {
        final lines = _chefCardLines(language);
        expect(lines, isNotEmpty);
        final violations = <String>[
          for (final line in lines)
            for (final words in _safeWords.values)
              for (final word in words)
                if (_holds(line, word)) '"$word" in: $line',
        ];
        expect(violations, isEmpty, reason: violations.join('\n'));
      });
    }
  });

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
