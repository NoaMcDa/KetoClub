// The chef card's sentence templates (Banto, ALG-08a and ALG-08b, issue
// #350; ALG-15, issue #357): one table over every restriction, in both
// languages, for the profile card, the dish card and the allergy note,
// plus the wording floor (no "safe", nothing the helper-tool statement
// disclaims).

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
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

/// Fails when [text] holds a banned word in either language.
void _expectInsideFloor(String text) {
  for (final banned in _bannedEnglish) {
    expect(
      _containsEnglish(text, banned),
      isFalse,
      reason: '"$text" contains "$banned"',
    );
  }
  for (final banned in _bannedHebrew) {
    expect(
      text.contains(banned),
      isFalse,
      reason: '"$text" contains "$banned"',
    );
  }
}

/// A kitchen signal of [kind] threatening [threatens].
KitchenSignal _signal(KitchenSignalKind kind, List<RestrictionId> threatens) =>
    KitchenSignal(
      kind: kind,
      threatens: threatens,
      evidence: const <String>['Fries'],
      questionEn: 'Is the fryer shared?',
      questionHe: 'האם המטגנת משותפת?',
    );

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

  group('ChefCardText.composeForDish', () {
    final sesameAndLactose = DietaryProfile.empty
        .withEntry(RestrictionId.sesame)
        .withEntry(RestrictionId.lactose);

    test('an empty profile has no card', () {
      expect(
        ChefCardText.composeForDish(
          DietaryProfile.empty,
          dishName: 'Salad',
          modification: null,
          questions: const <String>[],
          crossContact: true,
          hebrew: false,
        ),
        isEmpty,
      );
    });

    test('reads intro, the strict lines, the dish, its change, its '
        'questions, then thanks', () {
      // Act
      final lines = ChefCardText.composeForDish(
        sesameAndLactose,
        dishName: 'Tahini salad',
        modification: "Ask for it without 'tahini'",
        questions: const <String>['Can this be made without sesame?'],
        crossContact: false,
        hebrew: false,
      );

      // Assert: the lactose entry is flexible, so only sesame heads it.
      expect(lines, <String>[
        ChefCardText.compose(sesameAndLactose, hebrew: false).first,
        ChefCardText.compose(sesameAndLactose, hebrew: false)[1],
        'The dish I would like: Tahini salad',
        "Ask for it without 'tahini'",
        'Can this be made without sesame?',
        'Thank you.',
      ]);
    });

    test('a profile with no strict entry is headed by every entry', () {
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.lactose)
          .withEntry(RestrictionId.vegan);
      final lines = ChefCardText.composeForDish(
        profile,
        dishName: 'Omelette',
        modification: null,
        questions: const <String>[],
        crossContact: false,
        hebrew: false,
      );
      expect(lines[1], contains('lactose'));
      expect(lines[2], contains('vegan'));
      expect(lines[3], 'The dish I would like: Omelette');
    });

    test('a kitchen signal on a strict entry closes with cross-contact', () {
      for (final hebrew in <bool>[false, true]) {
        final lines = ChefCardText.composeForDish(
          _only(RestrictionId.sesame),
          dishName: 'סלט עם טחינה',
          modification: null,
          questions: const <String>[],
          crossContact: true,
          hebrew: hebrew,
        );
        expect(
          lines.last,
          ChefCardText.compose(
            _only(RestrictionId.sesame),
            hebrew: hebrew,
          ).last,
        );
        expect(lines.last, contains(hebrew ? 'מגע צולב' : 'cross-contact'));
      }
    });

    test('the Hebrew card names the dish as printed and keeps every '
        'question, multi-line changes split, blanks dropped', () {
      // Act
      final lines = ChefCardText.composeForDish(
        _only(RestrictionId.sesame),
        dishName: '  סלט עם טחינה ',
        modification: "לבקש את המנה בלי 'טחינה'\n\n לבקש בלי 'שומשום' ",
        questions: const <String>[
          'אפשר להכין את המנה בלי שומשום?',
          '  ',
          "בתפריט כתוב 'אגוזים' — האם יש בזה בוטנים?",
        ],
        crossContact: false,
        hebrew: true,
      );

      // Assert
      expect(lines, <String>[
        'שלום, יש לי הגבלות תזונה ואשמח לעזרתכם בהזמנה.',
        ChefCardText.compose(_only(RestrictionId.sesame), hebrew: true)[1],
        'המנה שאני רוצה להזמין: סלט עם טחינה',
        "לבקש את המנה בלי 'טחינה'",
        "לבקש בלי 'שומשום'",
        'אפשר להכין את המנה בלי שומשום?',
        "בתפריט כתוב 'אגוזים' — האם יש בזה בוטנים?",
        'תודה.',
      ]);
    });

    for (final restriction in restrictionTaxonomy) {
      for (final hebrew in <bool>[false, true]) {
        for (final crossContact in <bool>[false, true]) {
          test('${restriction.id.name} '
              '(${restriction.isStrict ? 'strict' : 'flexible'}) '
              '${hebrew ? 'he' : 'en'} crossContact=$crossContact stays '
              'inside the wording floor', () {
            final lines = ChefCardText.composeForDish(
              _only(restriction.id),
              dishName: 'Dish',
              modification: null,
              questions: const <String>[],
              crossContact: crossContact,
              hebrew: hebrew,
            );
            expect(lines, hasLength(4));
            lines.forEach(_expectInsideFloor);
          });
        }
      }
    }
  });

  group('ChefCardText.kitchenThreatensStrict', () {
    final fryer = _signal(KitchenSignalKind.fryer, const <RestrictionId>[
      RestrictionId.wheat,
      RestrictionId.gluten,
    ]);

    test('a signal on a strict entry of the profile counts', () {
      expect(
        ChefCardText.kitchenThreatensStrict(<KitchenSignal>[
          fryer,
        ], _only(RestrictionId.gluten)),
        isTrue,
      );
    });

    test('a signal on a restriction the profile does not hold does not', () {
      expect(
        ChefCardText.kitchenThreatensStrict(<KitchenSignal>[
          fryer,
        ], _only(RestrictionId.sesame)),
        isFalse,
      );
    });

    test('a signal on a flexible entry does not', () {
      final dairy = _signal(KitchenSignalKind.bakery, const <RestrictionId>[
        RestrictionId.lactose,
      ]);
      expect(
        ChefCardText.kitchenThreatensStrict(<KitchenSignal>[
          dairy,
        ], _only(RestrictionId.lactose)),
        isFalse,
      );
    });

    test('no signal, nothing', () {
      expect(
        ChefCardText.kitchenThreatensStrict(
          const <KitchenSignal>[],
          _only(RestrictionId.sesame),
        ),
        isFalse,
      );
    });
  });

  group('ChefCardText.allergyNote', () {
    test('keto alone, or nothing, has no note', () {
      expect(
        ChefCardText.allergyNote(DietaryProfile.empty, hebrew: false),
        isNull,
      );
      expect(
        ChefCardText.allergyNote(_only(RestrictionId.keto), hebrew: true),
        isNull,
      );
    });

    test('the Hebrew sesame note matches the epic, without a severity '
        'word', () {
      final note = ChefCardText.allergyNote(
        _only(RestrictionId.sesame),
        hebrew: true,
      );
      expect(
        note,
        'יש לי אלרגיה לשומשום. בבקשה לבדוק כל מרכיב, כולל רטבים, ולוודא '
        'שאין מגע צולב בהכנה. תודה.',
      );
      expect(note, isNot(contains('חמורה')));
    });

    test('several allergens join in a list, celiac and the flexible '
        'entries follow, keto is left out', () {
      // Arrange
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.sesame)
          .withEntry(RestrictionId.keto)
          .withEntry(RestrictionId.peanuts)
          .withEntry(RestrictionId.gluten)
          .withEntry(RestrictionId.treeNuts)
          .withEntry(RestrictionId.lactose);

      // Act
      final en = ChefCardText.allergyNote(profile, hebrew: false);
      final he = ChefCardText.allergyNote(profile, hebrew: true);

      // Assert
      expect(
        en,
        'I have an allergy to sesame, peanuts and tree nuts. I have celiac '
        'disease and cannot eat gluten. I also avoid lactose. Please check '
        'every ingredient, including sauces, and make sure there is no '
        'cross-contact in preparation. Thank you.',
      );
      expect(he, startsWith('יש לי אלרגיה לשומשום, לבוטנים ולאגוזי עץ. '));
      expect(he, contains('יש לי צליאק'));
      expect(he, contains('אני גם נמנע/ת מלקטוז.'));
      expect(en!.length, lessThanOrEqualTo(allergyNoteMaxLength));
      expect(he!.length, lessThanOrEqualTo(allergyNoteMaxLength));
    });

    test('a flexible-only profile asks for them to be left out', () {
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.lactose)
          .withEntry(RestrictionId.vegetarian);
      expect(
        ChefCardText.allergyNote(profile, hebrew: false),
        'I avoid lactose and meat, poultry or fish. Please leave them out of '
        'my order. Thank you.',
      );
      expect(
        ChefCardText.allergyNote(profile, hebrew: true),
        'אני נמנע/ת מלקטוז ומבשר, עוף או דגים. בבקשה לא לכלול אותם בהזמנה. '
        'תודה.',
      );
    });

    test('a long note drops the flexible sentence, never an allergen', () {
      // Arrange: every restriction at once.
      final everything = DietaryProfile(
        entries: <ProfileEntry>[
          for (final restriction in restrictionTaxonomy)
            ProfileEntry(restrictionId: restriction.id),
        ],
      );

      for (final hebrew in <bool>[false, true]) {
        // Act
        final note = ChefCardText.allergyNote(everything, hebrew: hebrew)!;

        // Assert
        for (final restriction in restrictionTaxonomy) {
          if (restriction.kind != RestrictionKind.allergen) continue;
          expect(
            note,
            contains(
              hebrew ? restriction.nameHe : restriction.nameEn.toLowerCase(),
            ),
          );
        }
        expect(note, isNot(contains(hebrew ? 'נמנע/ת' : 'avoid')));
      }
    });

    for (final restriction in restrictionTaxonomy) {
      if (restriction.id == RestrictionId.keto) continue;
      for (final hebrew in <bool>[false, true]) {
        test('${restriction.id.name} ${hebrew ? 'he' : 'en'}: one short '
            'note in its language, inside the wording floor', () {
          final note = ChefCardText.allergyNote(
            _only(restriction.id),
            hebrew: hebrew,
          )!;
          expect(note.length, lessThanOrEqualTo(allergyNoteMaxLength));
          expect(note, isNot(contains('\n')));
          expect(RegExp('[֐-׿]').hasMatch(note), hebrew);
          expect(
            note,
            contains(
              restriction.isStrict
                  ? (hebrew ? 'מגע צולב' : 'cross-contact')
                  : (hebrew ? 'לא לכלול' : 'leave them out'),
            ),
          );
          _expectInsideFloor(note);
        });
      }
    }
  });
}
