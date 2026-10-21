// Kosher and halal's vocabulary (Banto, issue #342): components only, never
// certification. English and Hebrew triggers with their prefix forms, the
// guards that name another food (turkey bacon, בייקון טבעוני, non-alcoholic
// beer, wine vinegar, cherry tomatoes), the reuse of the sea and alpha-gal
// lists, and the meat words of the meat-with-dairy rule.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocab_extended.dart';
import 'package:ketoclub/utils/allergens/vocab_religious.dart';
import 'package:ketoclub/utils/allergens/vocab_sea.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

const RestrictionId _kosher = RestrictionId.kosher;
const RestrictionId _halal = RestrictionId.halal;

/// The surest certainty [id] gets on [text], or null for no hit.
TriggerCertainty? _surest(String text, RestrictionId id) {
  TriggerCertainty? best;
  for (final hit in AllergenMatcher.find(text)) {
    if (hit.id != id) continue;
    if (best == null || hit.certainty.index < best.index) best = hit.certainty;
  }
  return best;
}

/// Whether [id]'s hits on [text] exist and every one is guarded.
bool _lowered(String text, RestrictionId id) {
  final hits = AllergenMatcher.find(text).where((hit) => hit.id == id);
  return hits.isNotEmpty &&
      hits.every(
        (hit) => hit.guarded && hit.certainty == TriggerCertainty.suspected,
      );
}

void main() {
  group('the religious vocabulary', () {
    test('covers kosher and halal, both religious components', () {
      expect(religiousVocabulary.keys.toSet(), <RestrictionId>{
        _kosher,
        _halal,
      });
      expect(
        identical(allergenVocabulary[_kosher], religiousVocabulary[_kosher]),
        isTrue,
      );
    });

    test('reuses the shellfish and mammal-meat lists rather than copying '
        'them', () {
      final kosher = religiousVocabulary[_kosher]!;
      expect(kosher.directEn, containsAll(crustaceanNamesEn));
      expect(kosher.directEn, containsAll(molluscNamesEn));
      expect(kosher.directEn, containsAll(shellfishNamesEn));
      expect(kosher.directHe, containsAll(crustaceanNamesHe));
      expect(kosher.directHe, containsAll(molluscNamesHe));
      final meat = meatWithDairyMeatVocabulary[_kosher]!;
      expect(meat.directEn, containsAll(mammalMeatEn));
      expect(meat.directEn, containsAll(mammalOffalCutsEn));
      expect(meat.directHe, containsAll(mammalMeatHe));
      expect(meat.directHe, containsAll(mammalCutsHe));
    });

    test('the sea and alpha-gal entries are their pieces, in order', () {
      final crustaceans = allergenVocabulary[RestrictionId.crustaceans]!;
      expect(crustaceans.directEn, <String>[
        ...crustaceanNamesEn,
        ...shellfishNamesEn,
      ]);
      final molluscs = allergenVocabulary[RestrictionId.molluscs]!;
      expect(molluscs.directHe, <String>[
        ...molluscNamesHe,
        ...shellfishNamesHe,
      ]);
      final alphaGal = allergenVocabulary[RestrictionId.alphaGal]!;
      expect(alphaGal.directEn.take(mammalMeatEn.length), mammalMeatEn);
      expect(
        alphaGal.directEn.skip(alphaGal.directEn.length - 11),
        mammalOffalCutsEn,
      );
    });

    test('poultry is meat for the meat-with-dairy rule; fish never is', () {
      final meat = meatWithDairyMeatVocabulary[_kosher]!;
      expect(meat.directEn, containsAll(<String>['chicken', 'turkey']));
      expect(meat.directHe, containsAll(<String>['עוף', 'הודו']));
      for (final fish in <String>['fish', 'salmon', 'tuna', 'דג', 'סלמון']) {
        expect(meat.directEn, isNot(contains(fish)));
        expect(meat.directHe, isNot(contains(fish)));
      }
    });
  });

  group('kosher', () {
    final table = <(String, TriggerCertainty?)>[
      // Pork, stated in English and Hebrew, with the prefixed forms.
      ('Pulled pork sandwich', TriggerCertainty.stated),
      ('Eggs with bacon', TriggerCertainty.stated),
      ('Prosciutto and melon', TriggerCertainty.stated),
      ('צלעות חזיר', TriggerCertainty.stated),
      ('סטייק החזיר', TriggerCertainty.stated),
      ('נתחי בחזיר', TriggerCertainty.stated),
      // A prefix letter never turns "returns" into pork.
      ('השף מחזיר את המנה', null),
      // Israel's euphemism, likely; cured meats, likely or suspected.
      ('סטייק לבן על הגריל', TriggerCertainty.likely),
      ('בשר לבן בגריל', TriggerCertainty.likely),
      ('פיצה עם בייקון', TriggerCertainty.likely),
      ('Pizza with pepperoni', TriggerCertainty.suspected),
      ('סלמי', TriggerCertainty.suspected),
      // Shellfish and fish without fins and scales.
      ('Shrimp tempura', TriggerCertainty.stated),
      ('מולים ביין לבן', TriggerCertainty.stated),
      ('Grilled eel', TriggerCertainty.stated),
      ('שפמנון מטוגן', TriggerCertainty.stated),
      ('Monkfish medallions', TriggerCertainty.stated),
      ('Sturgeon', TriggerCertainty.likely),
      ('Blini with caviar', TriggerCertainty.likely),
      ('Swordfish steak', TriggerCertainty.suspected),
      ('דג חרב', TriggerCertainty.suspected),
      // Other animals and blood.
      ('Braised rabbit', TriggerCertainty.stated),
      ('ארנבת ביין', TriggerCertainty.stated),
      ('Black pudding', TriggerCertainty.stated),
      ('נקניק דם', TriggerCertainty.stated),
      // Meat and cheese in one word.
      ('Bacon cheeseburger', TriggerCertainty.stated),
      ("צ'יזבורגר כפול", TriggerCertainty.stated),
      // Gelatin is suspected: it may be fish or plant-based.
      ('Panna cotta', TriggerCertainty.suspected),
      ("ג'לטין", TriggerCertainty.suspected),
      // A fish with fins and scales, poultry, and beef are none of these.
      ('Grilled salmon', null),
      ('חזה עוף', null),
      ('Beef kebab', null),
    ];
    for (final (text, expected) in table) {
      test('"$text" → ${expected?.name ?? 'nothing'}', () {
        expect(_surest(text, _kosher), expected);
      });
    }

    test('a guard lowers: turkey, beef, vegan and kosher bacon, goose '
        'prosciutto, salmon caviar, eel sauce', () {
      for (final text in <String>[
        'Turkey bacon',
        'Beef bacon',
        'Vegan bacon',
        'Kosher bacon',
        'בייקון טבעוני',
        'בייקון בקר',
        'פרושוטו אווז',
        'Salmon caviar',
        'Eel sauce',
        'רוטב אונאגי',
        'Shrimp-free',
      ]) {
        expect(_lowered(text, _kosher), isTrue, reason: text);
      }
    });

    test('an oyster mushroom and a crab apple are no shellfish', () {
      expect(_lowered('Oyster mushroom', _kosher), isTrue);
      expect(_lowered('Crab apple', _kosher), isTrue);
    });
  });

  group('halal', () {
    final table = <(String, TriggerCertainty?)>[
      ('Pork belly', TriggerCertainty.stated),
      ('Ham and cheese', TriggerCertainty.stated),
      ("פסטה עם פנצ'טה", TriggerCertainty.likely),
      ('Blood sausage', TriggerCertainty.stated),
      // Alcohol: hidden and likely, in a drink or cooked into a sauce.
      ('Red wine', TriggerCertainty.likely),
      ('Beer-battered fish', TriggerCertainty.likely),
      ('Penne alla vodka', TriggerCertainty.likely),
      ('Chicken marsala', TriggerCertainty.likely),
      ('Beef bourguignon', TriggerCertainty.likely),
      ('Coq au vin', TriggerCertainty.likely),
      ('Teriyaki salmon', TriggerCertainty.suspected),
      ('Tiramisu', TriggerCertainty.suspected),
      ('עוף ברוטב יין', TriggerCertainty.likely),
      ('בירה מהחבית', TriggerCertainty.likely),
      ('ריזוטו פטריות', TriggerCertainty.suspected),
      ('קוקטייל הבית', TriggerCertainty.likely),
      ("ג'לטין", TriggerCertainty.suspected),
      // "שרי" is the cherry tomato on an Israeli menu, never sherry.
      ('סלט עגבניות שרי', null),
      // Shellfish is not a halal component here: the schools differ.
      ('Shrimp tempura', null),
      // Meat with dairy is kosher's rule, not halal's.
      ('Cheeseburger', null),
      ('Lamb chops', null),
    ];
    for (final (text, expected) in table) {
      test('"$text" → ${expected?.name ?? 'nothing'}', () {
        expect(_surest(text, _halal), expected);
      });
    }

    test('a guard lowers: non-alcoholic, alcohol-free, ללא אלכוהול, wine '
        'vinegar, root beer, malt beer, a shrimp cocktail, salmon sake', () {
      for (final text in <String>[
        'Non-alcoholic beer',
        'Alcohol-free beer',
        'בירה ללא אלכוהול',
        'יין נטול אלכוהול',
        'Red wine vinegar',
        'חומץ יין',
        'Root beer',
        'בירה שחורה',
        'Shrimp cocktail',
        'Cocktail sauce',
        'Sake nigiri',
        'Halal pepperoni',
        'Turkey bacon',
      ]) {
        expect(_lowered(text, _halal), isTrue, reason: text);
      }
    });
  });

  group('religiousComponents', () {
    test('every component has a subject in both languages and words', () {
      for (final component in religiousComponents) {
        expect(component.subjectEn.trim(), isNotEmpty);
        expect(component.subjectHe.trim(), isNotEmpty);
        expect(component.vocabulary[_kosher]!.isEmpty, isFalse);
      }
    });

    test('no subject names kosher or halal', () {
      for (final component in religiousComponents) {
        for (final subject in <String>[
          component.subjectEn,
          component.subjectHe,
        ]) {
          expect(subject.toLowerCase(), isNot(contains('kosher')));
          expect(subject.toLowerCase(), isNot(contains('halal')));
          expect(subject, isNot(contains('כשר')));
          expect(subject, isNot(contains('חלאל')));
        }
      }
    });
  });
}
