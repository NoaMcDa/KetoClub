// The waiter question on every concern (Banto, ALG-08b, issue #350): one
// table over restriction × certainty × source × language, plus the
// wording floor (no "safe", nothing the helper-tool statement disclaims).

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/waiter_questions.dart';

/// English fragments no question may contain (as the chef card's test).
const _bannedEnglish = <String>[
  'safe',
  'diagnos',
  'treat',
  'cure',
  'medical',
  'guarantee',
  '100%',
];

/// Hebrew fragments no question may contain.
const _bannedHebrew = <String>[
  'בטוח',
  'מאבחן',
  'אבחון',
  'מטפל',
  'טיפול רפואי',
  'מבטיח',
];

/// A Hebrew letter.
final RegExp _hebrewLetter = RegExp('[֐-׿]');

Concern _concern(
  RestrictionId id, {
  ConcernSource source = ConcernSource.name,
  Certainty certainty = Certainty.stated,
  String? matched,
  String? question,
}) => Concern(
  restrictionId: id,
  source: source,
  certainty: certainty,
  tier: EvidenceTier.stated,
  matchedText: matched,
  waiterQuestion: question,
);

void main() {
  group('WaiterQuestions.questionFor — the epic examples', () {
    test('stated in the name: "Can this be made without sesame?"', () {
      final concern = _concern(RestrictionId.sesame, matched: 'tahini');
      expect(
        WaiterQuestions.questionFor(concern, hebrew: false),
        'Can this be made without sesame?',
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: true),
        'אפשר להכין את המנה בלי שומשום?',
      );
    });

    test('a hidden source quotes the menu and asks about the restriction', () {
      final concern = _concern(
        RestrictionId.wheat,
        source: ConcernSource.hidden,
        certainty: Certainty.likely,
        matched: 'soy sauce',
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: false),
        "The menu says 'soy sauce': does it contain wheat?",
      );
      final hebrew = _concern(
        RestrictionId.wheat,
        source: ConcernSource.hidden,
        certainty: Certainty.likely,
        matched: 'רוטב סויה',
      );
      expect(
        WaiterQuestions.questionFor(hebrew, hebrew: true),
        "בתפריט כתוב 'רוטב סויה' — האם יש בזה חיטה?",
      );
    });

    test('a stated hidden source still asks rather than demands', () {
      final concern = _concern(
        RestrictionId.fish,
        source: ConcernSource.hidden,
        matched: 'Worcestershire',
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: false),
        "The menu says 'Worcestershire': does it contain fish?",
      );
    });

    test('an option asks to leave the option off, quoting it', () {
      final concern = _concern(
        RestrictionId.milk,
        source: ConcernSource.option,
        matched: 'feta',
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: false),
        "Can this be served without 'feta', so there is no milk in it?",
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.milk,
            source: ConcernSource.option,
            matched: 'פטה',
          ),
          hebrew: true,
        ),
        "אפשר להגיש את המנה בלי 'פטה', כדי שלא יהיה בה חלב?",
      );
    });

    test('a suspected finding in the name quotes the words', () {
      final concern = _concern(
        RestrictionId.peanuts,
        certainty: Certainty.suspected,
        matched: 'אגוזים',
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: true),
        "בתפריט כתוב 'אגוזים' — האם יש בזה בוטנים?",
      );
    });

    test("a model's ingredient is asked about as an ingredient", () {
      final concern = _concern(
        RestrictionId.sesame,
        source: ConcernSource.model,
        certainty: Certainty.likely,
        matched: 'house dressing',
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: false),
        "Is there 'house dressing' in this dish, and does it contain "
        'sesame?',
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.sesame,
            source: ConcernSource.model,
            certainty: Certainty.suspected,
            matched: 'רוטב הבית',
          ),
          hebrew: true,
        ),
        "האם יש במנה 'רוטב הבית', והאם יש בזה שומשום?",
      );
    });

    test('words that are only the restriction itself are not quoted', () {
      // A guarded "ללא שומשום" is lowered to suspected and matched on
      // "שומשום": quoting it back would ask whether sesame holds sesame.
      final concern = _concern(
        RestrictionId.sesame,
        certainty: Certainty.suspected,
        matched: 'שומשום',
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: true),
        'האם יש במנה שומשום, גם ברוטב או בתוספת?',
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.sesame,
            certainty: Certainty.suspected,
            matched: 'Sesame',
          ),
          hebrew: true,
        ),
        'האם יש במנה שומשום, גם ברוטב או בתוספת?',
      );
    });

    test('with nothing to quote, the general question', () {
      final concern = _concern(
        RestrictionId.celery,
        source: ConcernSource.model,
        certainty: Certainty.suspected,
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: false),
        'Does this dish contain celery, even in a sauce, a dressing or a '
        'garnish?',
      );
    });

    test('a slice too long to be an ingredient is not quoted', () {
      final concern = _concern(
        RestrictionId.soy,
        certainty: Certainty.likely,
        matched: 'x' * 41,
      );
      expect(
        WaiterQuestions.questionFor(concern, hebrew: false),
        startsWith('Does this dish contain soy'),
      );
    });

    test('a diet is asked about as what it leaves out', () {
      final vegan = _concern(RestrictionId.vegan, matched: 'beef');
      expect(
        WaiterQuestions.questionFor(vegan, hebrew: false),
        'Can this be made without animal products (meat, fish, dairy, '
        'eggs or honey)?',
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(RestrictionId.vegetarian, matched: 'עוף'),
          hebrew: true,
        ),
        'אפשר להכין את המנה בלי בשר, עוף או דגים?',
      );
    });
  });

  group('every restriction × certainty × source × language', () {
    for (final restriction in restrictionTaxonomy) {
      for (final certainty in Certainty.values) {
        for (final source in ConcernSource.values) {
          for (final hebrew in <bool>[false, true]) {
            for (final matched in <String?>[null, 'x-item']) {
              final language = hebrew ? 'he' : 'en';
              test('${restriction.id.name} ${certainty.name} '
                  '${source.name} $language '
                  '${matched == null ? 'unquoted' : 'quoted'}', () {
                // Act
                final question = WaiterQuestions.questionFor(
                  _concern(
                    restriction.id,
                    source: source,
                    certainty: certainty,
                    matched: matched,
                  ),
                  hebrew: hebrew,
                );

                // Assert: a question, in its language, naming what is
                // avoided, inside the wording floor.
                expect(question.trim(), isNotEmpty);
                expect(question, endsWith('?'));
                expect(question, isNot(contains('{')));
                // The user's own restriction (ALG-17) names the words
                // it matched rather than its taxonomy subject.
                expect(
                  question,
                  contains(
                    restriction.id == RestrictionId.custom && matched != null
                        ? matched
                        : WaiterQuestions.subject(
                            restriction.id,
                            hebrew: hebrew,
                          ),
                  ),
                );
                expect(_hebrewLetter.hasMatch(question), hebrew);
                for (final banned in _bannedEnglish) {
                  expect(
                    RegExp(
                      '(?<![A-Za-z])${RegExp.escape(banned)}',
                      caseSensitive: false,
                    ).hasMatch(question),
                    isFalse,
                    reason: '"$question" contains "$banned"',
                  );
                }
                for (final banned in _bannedHebrew) {
                  expect(question.contains(banned), isFalse, reason: question);
                }
              });
            }
          }
        }
      }
    }
  });

  group('WaiterQuestions.fill', () {
    test('fills every missing or blank question in the given language', () {
      // Arrange
      final concerns = <Concern>[
        _concern(RestrictionId.sesame, matched: 'טחינה'),
        _concern(RestrictionId.eggs, question: '   '),
      ];

      // Act
      final filled = WaiterQuestions.fill(concerns, hebrew: true);

      // Assert
      expect(filled[0].waiterQuestion, 'אפשר להכין את המנה בלי שומשום?');
      expect(filled[1].waiterQuestion, 'אפשר להכין את המנה בלי ביצים?');
    });

    test('keeps a question the model wrote, and every other field', () {
      // Arrange
      final model = _concern(
        RestrictionId.peanuts,
        source: ConcernSource.model,
        certainty: Certainty.suspected,
        matched: 'satay',
        question: 'Is the satay made with peanuts?',
      );

      // Act
      final filled = WaiterQuestions.fill(<Concern>[model], hebrew: false);

      // Assert
      expect(filled.single, model);
    });

    test('changes nothing but the question, and keeps the order', () {
      // Arrange
      final concerns = <Concern>[
        _concern(
          RestrictionId.milk,
          source: ConcernSource.option,
          certainty: Certainty.likely,
          matched: 'cheese',
        ),
        _concern(RestrictionId.sesame),
      ];

      // Act
      final filled = WaiterQuestions.fill(concerns, hebrew: false);

      // Assert
      for (var i = 0; i < concerns.length; i++) {
        expect(filled[i].restrictionId, concerns[i].restrictionId);
        expect(filled[i].source, concerns[i].source);
        expect(filled[i].certainty, concerns[i].certainty);
        expect(filled[i].tier, concerns[i].tier);
        expect(filled[i].matchedText, concerns[i].matchedText);
        expect(filled[i].waiterQuestion, isNotNull);
      }
      expect(() => filled.add(concerns.first), throwsUnsupportedError);
    });

    test('an empty list stays empty', () {
      expect(WaiterQuestions.fill(const <Concern>[], hebrew: false), isEmpty);
    });
  });

  group('ALG-17 questions', () {
    test('FODMAP and histamine ask for less, quoting the menu', () {
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.fodmap,
            certainty: Certainty.suspected,
            matched: 'onion',
          ),
          hebrew: false,
        ),
        'I go easy on onion, garlic and other high-FODMAP foods. The menu '
        "says 'onion': can this be made with less of it?",
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.histamine,
            certainty: Certainty.suspected,
            matched: 'פרמזן',
          ),
          hebrew: true,
        ),
        'אני ממעיט/ה במזונות מיושנים, מעושנים, כבושים או מותססים. '
        "בתפריט כתוב 'פרמזן' — אפשר להכין את המנה עם פחות מזה?",
      );
    });

    test('small portions ask for a smaller or lighter version', () {
      expect(
        WaiterQuestions.questionFor(
          _concern(RestrictionId.glp1, certainty: Certainty.suspected),
          hebrew: false,
        ),
        'I go easy on large portions and fried, creamy or very sweet food. '
        'Is there a smaller or lighter version of this dish?',
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.glp1,
            certainty: Certainty.suspected,
            matched: 'מטוגן',
          ),
          hebrew: true,
        ),
        'אני ממעיט/ה במנות גדולות ומזון מטוגן, שמנתי או מתוק מאוד. '
        "בתפריט כתוב 'מטוגן' — יש גרסה קטנה או קלה יותר של המנה?",
      );
    });

    test('a heads-up never asks for a dish "without" anything', () {
      for (final id in headsUpRestrictions) {
        for (final hebrew in <bool>[false, true]) {
          final question = WaiterQuestions.questionFor(
            _concern(id, matched: 'x-item'),
            hebrew: hebrew,
          );
          expect(question, isNot(contains('without')));
          expect(question, isNot(contains('בלי')));
        }
      }
    });

    test('alpha-gal names its foods', () {
      expect(
        WaiterQuestions.questionFor(
          _concern(RestrictionId.alphaGal, matched: 'Beef'),
          hebrew: false,
        ),
        'Can this be made without mammal meat or its products (beef, lamb, '
        'pork, gelatin or lard)?',
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.alphaGal,
            source: ConcernSource.hidden,
            certainty: Certainty.likely,
            matched: 'קבב',
          ),
          hebrew: true,
        ),
        "בתפריט כתוב 'קבב' — האם יש בזה בשר יונקים או מוצריו (בקר, כבש, "
        "חזיר, ג'לטין או שומן מן החי)?",
      );
    });

    test('the own restriction names the word, as the user wrote it', () {
      // Arrange
      final concern = _concern(RestrictionId.custom, matched: 'ובכוסברה');

      // Act + Assert
      expect(
        WaiterQuestions.questionFor(concern, hebrew: true, ownWord: 'כוסברה'),
        'אפשר להכין את המנה בלי כוסברה?',
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.custom,
            certainty: Certainty.suspected,
            matched: 'kiwi',
          ),
          hebrew: false,
          ownWord: 'kiwi',
        ),
        'Does this dish contain kiwi, even in a sauce, a dressing or a '
        'garnish?',
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(RestrictionId.custom),
          hebrew: false,
        ),
        'Can this be made without the foods I listed?',
      );
    });
  });

  group('issue #342', () {
    test('oral allergy syndrome asks whether it is raw and can be cooked', () {
      expect(
        WaiterQuestions.questionFor(
          _concern(
            RestrictionId.oralAllergy,
            certainty: Certainty.suspected,
            matched: 'apple',
          ),
          hebrew: false,
        ),
        'I go easy on raw fruit and raw vegetables. The menu says '
        "'apple': is it raw, and can it be served cooked?",
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(RestrictionId.oralAllergy, certainty: Certainty.suspected),
          hebrew: true,
        ),
        'אני ממעיט/ה בפירות וירקות לא מבושלים. יש כאלה במנה שאינם '
        'מבושלים, ואפשר להגיש אותם מבושלים?',
      );
    });

    test('the dose sensitivities ask for less', () {
      expect(
        WaiterQuestions.questionFor(
          _concern(RestrictionId.caffeine, certainty: Certainty.suspected),
          hebrew: false,
        ),
        'I go easy on coffee, tea, cola and other caffeine. Is there any in '
        'this dish, and can it be made with less?',
      );
    });

    test('fava asks for the beans, never "favism"', () {
      final question = WaiterQuestions.questionFor(
        _concern(RestrictionId.fava),
        hebrew: false,
      );
      expect(question, 'Can this be made without fava beans (broad beans)?');
      expect(
        WaiterQuestions.questionFor(_concern(RestrictionId.fava), hebrew: true),
        'אפשר להכין את המנה בלי פול?',
      );
    });

    test('a single food names itself; a diet names what it leaves out', () {
      expect(
        WaiterQuestions.questionFor(
          _concern(RestrictionId.chickpea),
          hebrew: true,
        ),
        'אפשר להכין את המנה בלי גרגרי חומוס?',
      );
      expect(
        WaiterQuestions.questionFor(
          _concern(RestrictionId.pescatarian),
          hebrew: false,
        ),
        'Can this be made without meat or poultry?',
      );
    });
  });
}
