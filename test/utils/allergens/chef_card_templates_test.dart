// The chef card's sentence templates (Banto, ALG-08a, issue #350): one
// table over every restriction, in both languages, plus the wording floor
// (no "safe", nothing the helper-tool statement disclaims).

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// English fragments no card line may contain: the claims the app does not
/// make (mirrors `test/l10n/banned_words_test.dart`) plus "safe".
const _bannedEnglish = <String>[
  'safe',
  'diagnos',
  'treat',
  'cure',
  'medical',
  'guarantee',
  '100%',
];

/// Hebrew fragments no card line may contain.
const _bannedHebrew = <String>[
  'בטוח',
  'בטוחה',
  'מאבחן',
  'אבחון',
  'מטפל',
  'טיפול רפואי',
  'מכשיר רפואי',
  'מבטיח',
];

DietaryProfile _only(RestrictionId id, {List<String>? exceptions}) =>
    DietaryProfile.empty.withEntry(id, exceptions: exceptions);

bool _containsEnglish(String line, String banned) => RegExp(
  '(?<![A-Za-z])${RegExp.escape(banned)}',
  caseSensitive: false,
).hasMatch(line);

void main() {
  group('ChefCardText.compose', () {
    test('an empty profile has no card', () {
      expect(
        ChefCardText.compose(DietaryProfile.empty, hebrew: false),
        isEmpty,
      );
      expect(ChefCardText.compose(DietaryProfile.empty, hebrew: true), isEmpty);
    });

    test('a profile reads intro, one line per entry, then a closing line', () {
      // Arrange
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.sesame)
          .withEntry(RestrictionId.lactose);

      // Act
      final lines = ChefCardText.compose(profile, hebrew: false);

      // Assert
      expect(lines, hasLength(4));
      expect(lines[1], contains('sesame'));
      expect(lines[2], contains('lactose'));
    });

    test('the lines follow profile order', () {
      // Arrange
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.fish)
          .withEntry(RestrictionId.eggs);

      // Act
      final lines = ChefCardText.compose(profile, hebrew: true);

      // Assert
      expect(lines[1], contains('דגים'));
      expect(lines[2], contains('ביצים'));
    });

    test('the composed list cannot be changed', () {
      final lines = ChefCardText.compose(
        _only(RestrictionId.sesame),
        hebrew: false,
      );
      expect(() => lines.add('x'), throwsUnsupportedError);
    });

    test('the English allergen sentence matches the epic', () {
      expect(
        ChefCardText.compose(_only(RestrictionId.sesame), hebrew: false)[1],
        'I have an allergy to sesame — please check every ingredient, '
        'including sauces, oils and garnishes.',
      );
    });

    test('the Hebrew allergen sentence prefixes the name with ל', () {
      expect(
        ChefCardText.compose(_only(RestrictionId.sesame), hebrew: true)[1],
        'יש לי אלרגיה לשומשום — נא לבדוק כל מרכיב, '
        'כולל רטבים, שמנים וקישוטים.',
      );
    });

    test('the English flexible sentence matches the epic', () {
      expect(
        ChefCardText.compose(_only(RestrictionId.lactose), hebrew: false)[1],
        'I avoid lactose — please tell me which dishes contain it.',
      );
    });

    test('celiac disease has its own sentence about gluten and '
        'cross-contact', () {
      // Act
      final en = ChefCardText.compose(
        _only(RestrictionId.gluten),
        hebrew: false,
      );
      final he = ChefCardText.compose(
        _only(RestrictionId.gluten),
        hebrew: true,
      );

      // Assert
      expect(en[1], contains('celiac disease'));
      expect(en[1], contains('gluten'));
      expect(en[1], contains('shared fryers'));
      expect(en[1], isNot(contains('I have an allergy')));
      expect(he[1], contains('צליאק'));
      expect(he[1], contains('גלוטן'));
      expect(he[1], contains('מגע צולב'));
    });

    test('a strict profile closes by asking the kitchen to confirm '
        'cross-contact precautions', () {
      expect(
        ChefCardText.compose(_only(RestrictionId.peanuts), hebrew: false).last,
        contains('cross-contact'),
      );
      expect(
        ChefCardText.compose(_only(RestrictionId.peanuts), hebrew: true).last,
        contains('מגע צולב'),
      );
    });

    test('a profile of flexible entries only closes with thanks', () {
      expect(
        ChefCardText.compose(_only(RestrictionId.lactose), hebrew: false).last,
        'Thank you.',
      );
      expect(
        ChefCardText.compose(_only(RestrictionId.vegan), hebrew: true).last,
        'תודה.',
      );
    });

    test('exceptions are rendered on the line of their entry', () {
      // Arrange
      final profile = _only(
        RestrictionId.lactose,
        exceptions: const <String>['butter', 'ghee'],
      );

      // Act
      final en = ChefCardText.compose(profile, hebrew: false);
      final he = ChefCardText.compose(profile, hebrew: true);

      // Assert
      expect(en, hasLength(3));
      expect(en[1], endsWith('I can still have: butter, ghee.'));
      expect(he[1], endsWith('אני כן יכול/ה לאכול: butter, ghee.'));
    });

    test('an entry with no exceptions mentions none', () {
      final line = ChefCardText.compose(
        _only(RestrictionId.lactose),
        hebrew: false,
      )[1];
      expect(line, isNot(contains('I can still have')));
    });

    test('asText joins the lines with a newline', () {
      expect(ChefCardText.asText(<String>['a', 'b']), 'a\nb');
    });
  });

  group('every restriction, every language', () {
    for (final restriction in restrictionTaxonomy) {
      for (final hebrew in <bool>[false, true]) {
        final language = hebrew ? 'he' : 'en';
        test('${restriction.id.name} (${restriction.kind.name}) in $language '
            'names itself and stays inside the wording floor', () {
          // Act
          final lines = ChefCardText.compose(
            _only(restriction.id),
            hebrew: hebrew,
          );
          final entryLine = lines[1];

          // Assert: intro, entry, closing; the entry line is not empty.
          expect(lines, hasLength(3));
          for (final line in lines) {
            expect(line.trim(), isNotEmpty);
            for (final banned in _bannedEnglish) {
              expect(
                _containsEnglish(line, banned),
                isFalse,
                reason: '"$line" contains "$banned"',
              );
            }
            for (final banned in _bannedHebrew) {
              expect(
                line.contains(banned),
                isFalse,
                reason: '"$line" contains "$banned"',
              );
            }
          }
          // Allergens and celiac name themselves; lifestyle and keto
          // sentences describe the diet instead of echoing its name.
          if (restriction.kind == RestrictionKind.allergen ||
              restriction.kind == RestrictionKind.intolerance ||
              restriction.kind == RestrictionKind.autoimmune) {
            expect(
              entryLine.toLowerCase(),
              contains(
                hebrew ? restriction.nameHe : restriction.nameEn.toLowerCase(),
              ),
            );
          }
          // The strict sentences ask for a check; the flexible ones ask
          // to be told.
          if (restriction.isStrict) {
            expect(
              hebrew
                  ? entryLine.contains('נא לבדוק כל מרכיב')
                  : entryLine.contains('please check every ingredient'),
              isTrue,
            );
          } else {
            expect(
              hebrew
                  ? entryLine.contains('נא לומר לי')
                  : entryLine.contains('please tell me'),
              isTrue,
            );
          }
        });
      }
    }

    test('a language never leaks into the other', () {
      // Arrange
      final everything = DietaryProfile(
        entries: <ProfileEntry>[
          for (final restriction in restrictionTaxonomy)
            ProfileEntry(restrictionId: restriction.id),
        ],
      );
      final hebrewLetter = RegExp('[֐-׿]');

      // Act
      final en = ChefCardText.compose(everything, hebrew: false);
      final he = ChefCardText.compose(everything, hebrew: true);

      // Assert
      for (final line in en) {
        expect(hebrewLetter.hasMatch(line), isFalse, reason: line);
      }
      for (final line in he) {
        expect(hebrewLetter.hasMatch(line), isTrue, reason: line);
      }
    });
  });
}
