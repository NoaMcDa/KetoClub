// The chef card in a trip destination's language (Banto, issue #419):
// French, Italian, Spanish, German and Japanese. The law's names (Annex II
// of Regulation (EU) No 1169/2011, Japan's Consumer Affairs Agency list)
// are pinned word for word; every sentence is pinned through its block;
// a restriction a block cannot name is named in English, never dropped.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/utils/allergens/chef_card_locales.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// The five translated languages.
const List<ChefCardLanguage> _translated = <ChefCardLanguage>[
  ChefCardLanguage.fr,
  ChefCardLanguage.it,
  ChefCardLanguage.es,
  ChefCardLanguage.de,
  ChefCardLanguage.ja,
];

/// A profile holding [ids], in order.
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

/// The restrictions whose line is their own sentence, naming no name.
const Set<RestrictionId> _ownSentence = <RestrictionId>{
  RestrictionId.keto,
  RestrictionId.vegan,
  RestrictionId.vegetarian,
  RestrictionId.kosher,
  RestrictionId.halal,
  RestrictionId.glp1,
};

/// A block with French sentences and no names, for the fallback rule.
const ChefCardLocale _nameless = ChefCardLocale(
  intro: 'intro',
  groupIntro: 'group intro',
  me: 'me',
  allergenLine: 'Allergie : {name}.',
  celiacLine: 'Cœliaque : {name}.',
  medicalLine: 'Santé : {name}.',
  avoidLine: "J'évite : {name}.",
  dietLine: 'Régime : {name}.',
  ketoLine: 'keto',
  veganLine: 'vegan',
  vegetarianLine: 'vegetarian',
  kosherLine: 'kosher',
  halalLine: 'halal',
  glp1Line: 'glp1',
  kosherQuestion: 'kosher?',
  halalQuestion: 'halal?',
  ownLine: 'Non : {list}.',
  exceptionsLine: 'Oui : {list}.',
  dishLine: 'Plat : {dish}',
  groupDishLine: 'Plat (nous) : {dish}',
  closingStrict: 'closing strict',
  closing: 'closing',
  footer: 'footer',
  names: <RestrictionId, String>{},
  officialNames: <RestrictionId>{},
);

void main() {
  group('ChefCardLanguage', () {
    test('a trip to France, Italy, Spain, Germany or Japan has its '
        'language; Israel, the US and the UK and no trip have none', () {
      expect(
        <TripDestination?, ChefCardLanguage?>{
          for (final trip in <TripDestination?>[
            ...TripDestination.values,
            null,
          ])
            trip: ChefCardLanguage.forTrip(trip),
        },
        <TripDestination?, ChefCardLanguage?>{
          TripDestination.israel: null,
          TripDestination.unitedStates: null,
          TripDestination.unitedKingdom: null,
          TripDestination.france: ChefCardLanguage.fr,
          TripDestination.italy: ChefCardLanguage.it,
          TripDestination.spain: ChefCardLanguage.es,
          TripDestination.germany: ChefCardLanguage.de,
          TripDestination.japan: ChefCardLanguage.ja,
          null: null,
        },
      );
    });

    test('Hebrew and English are not translated; the five are, and none '
        'has been reviewed by a native speaker', () {
      expect(ChefCardLanguage.he.isTranslated, isFalse);
      expect(ChefCardLanguage.en.isTranslated, isFalse);
      for (final language in _translated) {
        expect(language.isTranslated, isTrue, reason: language.name);
        expect(
          language.locale!.nativeSpeakerReviewed,
          isFalse,
          reason: language.name,
        );
      }
      expect(ChefCardLanguage.he.isRtl, isTrue);
      expect(_translated.any((language) => language.isRtl), isFalse);
    });
  });

  group('the law names (Annex II; the CAA list)', () {
    test('French, Italian, Spanish and German name the EU 14 and wheat as '
        'Annex II words them', () {
      const annex = <RestrictionId, List<String>>{
        // fr, it, es, de
        RestrictionId.gluten: <String>[
          'céréales contenant du gluten',
          'cereali contenenti glutine',
          'cereales que contengan gluten',
          'glutenhaltiges Getreide',
        ],
        RestrictionId.wheat: <String>['blé', 'grano', 'trigo', 'Weizen'],
        RestrictionId.crustaceans: <String>[
          'crustacés',
          'crostacei',
          'crustáceos',
          'Krebstiere',
        ],
        RestrictionId.eggs: <String>['œufs', 'uova', 'huevos', 'Eier'],
        RestrictionId.fish: <String>['poissons', 'pesce', 'pescado', 'Fische'],
        RestrictionId.peanuts: <String>[
          'arachides',
          'arachidi',
          'cacahuetes',
          'Erdnüsse',
        ],
        RestrictionId.soy: <String>['soja', 'soia', 'soja', 'Sojabohnen'],
        RestrictionId.milk: <String>['lait', 'latte', 'leche', 'Milch'],
        RestrictionId.treeNuts: <String>[
          'fruits à coque',
          'frutta a guscio',
          'frutos de cáscara',
          'Schalenfrüchte',
        ],
        RestrictionId.celery: <String>['céleri', 'sedano', 'apio', 'Sellerie'],
        RestrictionId.mustard: <String>[
          'moutarde',
          'senape',
          'mostaza',
          'Senf',
        ],
        RestrictionId.sesame: <String>[
          'graines de sésame',
          'semi di sesamo',
          'granos de sésamo',
          'Sesamsamen',
        ],
        RestrictionId.sulphites: <String>[
          'anhydride sulfureux et sulfites',
          'anidride solforosa e solfiti',
          'dióxido de azufre y sulfitos',
          'Schwefeldioxid und Sulphite',
        ],
        RestrictionId.lupin: <String>[
          'lupin',
          'lupini',
          'altramuces',
          'Lupinen',
        ],
        RestrictionId.molluscs: <String>[
          'mollusques',
          'molluschi',
          'moluscos',
          'Weichtiere',
        ],
      };
      const eu = <ChefCardLanguage>[
        ChefCardLanguage.fr,
        ChefCardLanguage.it,
        ChefCardLanguage.es,
        ChefCardLanguage.de,
      ];
      for (var i = 0; i < eu.length; i++) {
        final locale = eu[i].locale!;
        expect(locale.officialNames, annex.keys.toSet(), reason: eu[i].name);
        for (final MapEntry(:key, :value) in annex.entries) {
          expect(locale.names[key], value[i], reason: '${eu[i].name} $key');
        }
      }
    });

    test("Japanese names the CAA list's items as the list writes them", () {
      const caa = <RestrictionId, String>{
        RestrictionId.peanuts: '落花生（ピーナッツ）',
        RestrictionId.wheat: '小麦',
        RestrictionId.buckwheat: 'そば',
        RestrictionId.eggs: '卵',
        RestrictionId.milk: '乳',
        RestrictionId.soy: '大豆',
        RestrictionId.sesame: 'ごま',
        RestrictionId.kiwi: 'キウイフルーツ',
        RestrictionId.peach: 'もも',
        RestrictionId.apple: 'りんご',
        RestrictionId.banana: 'バナナ',
        RestrictionId.orange: 'オレンジ',
        RestrictionId.beef: '牛肉',
        RestrictionId.pork: '豚肉',
        RestrictionId.chicken: '鶏肉',
        RestrictionId.gelatin: 'ゼラチン',
        RestrictionId.yam: 'やまいも',
      };
      final locale = ChefCardLanguage.ja.locale!;
      expect(locale.officialNames, caa.keys.toSet());
      for (final MapEntry(:key, :value) in caa.entries) {
        expect(locale.names[key], value, reason: '$key');
      }
      // Built from the list's own names.
      expect(locale.names[RestrictionId.crustaceans], contains('えび'));
      expect(locale.names[RestrictionId.crustaceans], contains('かに'));
      for (final nut in <String>['くるみ', 'カシューナッツ', 'ピスタチオ']) {
        expect(locale.names[RestrictionId.treeNuts], contains(nut));
      }
    });

    test('every block names every restriction of the taxonomy', () {
      for (final language in _translated) {
        final locale = language.locale!;
        expect(
          <RestrictionId>[
            for (final restriction in restrictionTaxonomy)
              if (!ChefCardLocales.hasLocalName(restriction.id, locale))
                restriction.id,
          ],
          isEmpty,
          reason: language.name,
        );
      }
    });
  });

  group('the template table', () {
    for (final language in _translated) {
      group(language.name, () {
        final locale = language.locale!;
        String name(RestrictionId id) => locale.names[id]!;

        test('a strict profile (sesame): intro, the allergen sentence, the '
            'cross-contact closing', () {
          expect(
            ChefCardText.compose(
              _profile(<RestrictionId>[RestrictionId.sesame]),
              hebrew: false,
              language: language,
            ),
            <String>[
              locale.intro,
              locale.allergenLine.replaceAll(
                '{name}',
                name(RestrictionId.sesame),
              ),
              locale.closingStrict,
            ],
          );
        });

        test('celiac disease gets its own sentence, with the Annex II or '
            'translated gluten name', () {
          final lines = ChefCardText.compose(
            _profile(<RestrictionId>[RestrictionId.gluten]),
            hebrew: false,
            language: language,
          );
          expect(
            lines[1],
            locale.celiacLine.replaceAll('{name}', name(RestrictionId.gluten)),
          );
          expect(lines.last, locale.closingStrict);
        });

        test('a flexible profile (lactose, vegan, paleo) asks to be told '
            'and closes with thanks', () {
          expect(
            ChefCardText.compose(
              _profile(<RestrictionId>[
                RestrictionId.lactose,
                RestrictionId.vegan,
                RestrictionId.paleo,
              ]),
              hebrew: false,
              language: language,
            ),
            <String>[
              locale.intro,
              locale.avoidLine.replaceAll(
                '{name}',
                name(RestrictionId.lactose),
              ),
              locale.veganLine,
              locale.dietLine.replaceAll('{name}', name(RestrictionId.paleo)),
              locale.closing,
            ],
          );
        });

        test('fava is a medical line; kosher adds its certification '
            'question', () {
          final lines = ChefCardText.compose(
            _profile(<RestrictionId>[RestrictionId.fava, RestrictionId.kosher]),
            hebrew: false,
            language: language,
          );
          expect(lines, <String>[
            locale.intro,
            locale.medicalLine.replaceAll('{name}', name(RestrictionId.fava)),
            locale.kosherLine,
            locale.kosherQuestion,
            locale.closingStrict,
          ]);
        });

        test("exceptions and the user's own words keep the user's text", () {
          final profile = DietaryProfile.empty
              .withEntry(
                RestrictionId.treeNuts,
                exceptions: const <String>['coconut', 'nutmeg'],
              )
              .withEntry(
                RestrictionId.custom,
                terms: const <String>['kiwi', 'כוסברה'],
              );
          final lines = ChefCardText.compose(
            profile,
            hebrew: false,
            language: language,
          );
          final sep = locale.listSeparator;
          final base = locale.allergenLine.replaceAll(
            '{name}',
            name(RestrictionId.treeNuts),
          );
          final except = locale.exceptionsLine.replaceAll(
            '{list}',
            'coconut${sep}nutmeg',
          );
          expect(lines[1], '$base${locale.sentenceJoiner}$except');
          expect(
            lines[2],
            locale.ownLine.replaceAll('{list}', 'kiwi$sepכוסברה'),
          );
        });

        test('a dish card names the dish in the language and keeps the '
            "evaluator's lines as given", () {
          final lines = ChefCardText.composeForDish(
            _profile(<RestrictionId>[RestrictionId.milk]),
            dishName: 'Gratin dauphinois',
            modification: "Without 'crème'",
            questions: const <String>['Is there butter in the sauce?'],
            crossContact: false,
            hebrew: false,
            language: language,
          );
          expect(lines, <String>[
            locale.intro,
            locale.allergenLine.replaceAll('{name}', name(RestrictionId.milk)),
            locale.dishLine.replaceAll('{dish}', 'Gratin dauphinois'),
            "Without 'crème'",
            'Is there butter in the sauce?',
            locale.closing,
          ]);
          expect(
            ChefCardText.closingLine(
              crossContact: true,
              hebrew: false,
              language: language,
            ),
            locale.closingStrict,
          );
        });

        test('a group card greets, heads and names the dish in the '
            'language', () {
          const people = <NamedProfile>[NamedProfile(id: 'me', name: '')];
          final card = GroupChefCardText.compose(
            people,
            hebrew: false,
            language: language,
          );
          expect(card.intro, locale.groupIntro);
          expect(card.sections.single.heading, locale.me);
          expect(card.sections.single.lines, <String>[locale.ketoLine]);
          final dish = GroupChefCardText.composeForDish(
            <PersonDishPart>[
              (
                person: people.single,
                modification: null,
                questions: const <String>[],
              ),
            ],
            dishName: 'Ramen',
            crossContact: true,
            hebrew: false,
            language: language,
          );
          expect(
            dish.dishLine,
            locale.groupDishLine.replaceAll('{dish}', 'Ramen'),
          );
          expect(dish.closing, locale.closingStrict);
        });

        test("the image footer is the block's own", () {
          expect(ChefCardText.imageFooter(language), locale.footer);
          expect(locale.footer, startsWith('Banto · '));
        });

        test('no restriction is dropped: each one-entry card carries its '
            'name, or its own sentence', () {
          for (final restriction in restrictionTaxonomy) {
            if (restriction.id == RestrictionId.custom) continue;
            final lines = ChefCardText.compose(
              _profile(<RestrictionId>[restriction.id]),
              hebrew: false,
              language: language,
            );
            expect(lines, hasLength(greaterThanOrEqualTo(3)));
            if (_ownSentence.contains(restriction.id)) continue;
            expect(
              lines[1],
              contains(ChefCardLocales.nameOf(restriction.id, locale)),
              reason: '${language.name} ${restriction.id}',
            );
          }
        });
      });
    }
  });

  group('the English fallback', () {
    test('a restriction a block has no name for is named in English, on '
        'its own line, never dropped', () {
      final sesame = DietaryProfile.empty.withEntry(RestrictionId.sesame);
      expect(
        ChefCardLocales.entryLine(sesame.entries.single, _nameless),
        'Allergie : Sesame.',
      );
      expect(
        ChefCardLocales.hasLocalName(RestrictionId.sesame, _nameless),
        isFalse,
      );
      expect(
        ChefCardLocales.nameOf(RestrictionId.histamine, _nameless),
        restrictionFor(RestrictionId.histamine).nameEn,
      );
      final own = DietaryProfile.empty.withEntry(RestrictionId.custom);
      expect(
        ChefCardLocales.entryLine(own.entries.single, _nameless),
        'Non : Your own restriction.',
      );
    });
  });

  group('Hebrew and English are unchanged', () {
    final profile = DietaryProfile.empty
        .withEntry(RestrictionId.sesame)
        .withEntry(RestrictionId.kosher)
        .withEntry(RestrictionId.lactose, exceptions: const <String>['butter']);

    for (final hebrew in <bool>[false, true]) {
      test('language ${hebrew ? 'he' : 'en'} is the hebrew flag', () {
        final language = ChefCardLanguage.of(hebrew: hebrew);
        expect(
          ChefCardText.compose(profile, hebrew: !hebrew, language: language),
          ChefCardText.compose(profile, hebrew: hebrew),
        );
        expect(
          ChefCardText.dishLine('X', hebrew: !hebrew, language: language),
          ChefCardText.dishLine('X', hebrew: hebrew),
        );
        expect(
          ChefCardText.certificationQuestion(
            RestrictionId.halal,
            hebrew: !hebrew,
            language: language,
          ),
          ChefCardText.certificationQuestion(
            RestrictionId.halal,
            hebrew: hebrew,
          ),
        );
        expect(ChefCardText.imageFooter(language), startsWith('Banto · '));
      });
    }

    test('the English and Hebrew image footers', () {
      expect(
        ChefCardText.imageFooter(ChefCardLanguage.en),
        'Banto · a helper, not a guarantee — always ask the restaurant',
      );
      expect(
        ChefCardText.imageFooter(ChefCardLanguage.he),
        'Banto · כלי עזר, לא ערובה — תמיד לשאול את המסעדה',
      );
    });
  });
}
