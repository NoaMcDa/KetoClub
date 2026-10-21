/// Fish and seafood: the trigger vocabulary of fish, crustaceans and molluscs
/// (Banto; ALG-01, issue #343).
///
/// Every term comes from
/// `allergen app documentation/11_hidden_allergen_sources.md` or
/// `12_israeli_and_us_menu_lexicon.md` and its source cites the section
/// (`"11 §7.1"`, `"12 §1.4"`), which
/// `test/utils/allergens/vocabulary_test.dart` checks. After a change,
/// regenerate the goldens and copy `allergens.json` to
/// `backend/app/keto/` (architecture.md D26).
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// English fish triggers: the word and the named species (11 §8.1).
const List<String> _fishEn = <String>[
  'fish',
  'salmon',
  'tuna',
  'cod',
  'haddock',
  'halibut',
  'trout',
  'bream',
  'sea bass',
  'seabass',
  'branzino',
  'barramundi',
  'snapper',
  'grouper',
  'mackerel',
  'herring',
  'sardine',
  'sardines',
  'anchovy',
  'anchovies',
  'tilapia',
  'mullet',
  'swordfish',
  'carp',
  'pike',
  'perch',
  'catfish',
  'eel',
  'unagi',
  'monkfish',
  'flounder',
  'pollock',
  'mahi mahi',
  'dover sole',
  'bonito',
  'katsuobushi',
  'sashimi',
  'lox',
  'gravlax',
  'caviar',
  'roe',
  'bottarga',
  'nam pla',
  'nuoc mam',
  'bouillabaisse',
];

/// Hebrew fish triggers (11 §8.1, 12 §1.7); `חריימה` and `סביצ'ה` are
/// fish dishes.
const List<String> _fishHe = <String>[
  'דג',
  'דגים',
  'דגי',
  'פיש',
  'סלמון',
  'סלומון',
  'טונה',
  'לברק',
  'דניס',
  'פורל',
  'אמנון',
  'בורי',
  'ברמונדי',
  'הרינג',
  'מקרל',
  'סרדין',
  'סרדינים',
  'אנשובי',
  'קרפיון',
  'לוקוס',
  'סשימי',
  'סאשימי',
  'קוויאר',
  'קביאר',
  'בוטרגה',
  'חריימה',
  "סביצ'ה",
];

/// English crustacean names (11 §9.1): the head of [_crustaceansEn], public
/// so the kosher vocabulary (`vocab_religious.dart`) reads the same words.
const List<String> crustaceanNamesEn = <String>[
  'shrimp',
  'shrimps',
  'prawn',
  'prawns',
  'crab',
  'crabs',
  'lobster',
  'lobsters',
  'crayfish',
  'crawfish',
  'langoustine',
  'langoustines',
  'scampi',
  'krill',
  'bisque',
];

/// English words that name crustaceans and molluscs together (11 §9.1,
/// §10.1): the tail of both [_crustaceansEn] and [_molluscsEn].
const List<String> shellfishNamesEn = <String>[
  'seafood',
  'shellfish',
  'frutti di mare',
];

/// English crustacean triggers (11 §9.1). "Seafood" and "shellfish" name both
/// crustaceans and molluscs, so both carry them.
const List<String> _crustaceansEn = <String>[
  ...crustaceanNamesEn,
  ...shellfishNamesEn,
];

/// Hebrew crustacean names (11 §9.1, 12 §1.7): the head of
/// [_crustaceansHe], public for the kosher vocabulary.
const List<String> crustaceanNamesHe = <String>[
  'שרימפס',
  'שרימפסים',
  'סרטן',
  'סרטנים',
  'לובסטר',
  'לנגוסטין',
  'קראב',
];

/// Hebrew words that name crustaceans and molluscs together (12 §1.7): the
/// tail of both [_crustaceansHe] and [_molluscsHe].
const List<String> shellfishNamesHe = <String>['פירות ים', 'פירות הים'];

/// Hebrew crustacean triggers (11 §9.1, 12 §1.7). `פירות ים` names both
/// crustaceans and molluscs.
const List<String> _crustaceansHe = <String>[
  ...crustaceanNamesHe,
  ...shellfishNamesHe,
];

/// English mollusc names (11 §10.1): the head of [_molluscsEn], public for
/// the kosher vocabulary.
const List<String> molluscNamesEn = <String>[
  'mussel',
  'mussels',
  'moules',
  'clam',
  'clams',
  'oyster',
  'oysters',
  'scallop',
  'scallops',
  'squid',
  'calamari',
  'kalamari',
  'calamares',
  'octopus',
  'cuttlefish',
  'snail',
  'snails',
  'escargot',
  'whelk',
  'whelks',
  'cockle',
  'cockles',
  'abalone',
  'periwinkle',
  'vongole',
  'cozze',
];

/// English mollusc triggers (11 §10.1). `oyster` is guarded against the oyster
/// mushroom; the Hebrew `צדפה` is left out because `פטריות צדפה` is the
/// mushroom.
const List<String> _molluscsEn = <String>[
  ...molluscNamesEn,
  ...shellfishNamesEn,
];

/// Hebrew mollusc names (11 §10.1, 12 §1.7): the head of [_molluscsHe],
/// public for the kosher vocabulary.
const List<String> molluscNamesHe = <String>[
  'מולים',
  'צדפות',
  'סקאלופס',
  'סקאלופ',
  'קלמרי',
  'קלמארי',
  'תמנון',
  'תמנונים',
  'דיונון',
  'דיונונים',
  'חלזון',
  'חלזונות',
  'אסקרגו',
  'רכיכות',
];

/// Hebrew mollusc triggers (11 §10.1, 12 §1.7).
const List<String> _molluscsHe = <String>[
  ...molluscNamesHe,
  ...shellfishNamesHe,
];

/// English hidden sources of fish (11 §8.1, §8.2, §8.5, 12 §5).
const List<HiddenTrigger> _fishHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'surimi',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'fish sauce',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'worcestershire',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'worcester sauce',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'caesar',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'dashi',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.1',
  ),
  HiddenTrigger(
    term: 'miso soup',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.1',
  ),
  HiddenTrigger(
    term: 'isinglass',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.5',
  ),
  HiddenTrigger(
    term: 'kimchi',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'barbecue sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'bbq sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'puttanesca',
    certainty: TriggerCertainty.suspected,
    source: '12 §5',
  ),
  // Recall-gate additions (issue #352).
  HiddenTrigger(
    term: 'curry paste',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.1',
  ),
  HiddenTrigger(
    term: 'massaman',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.1',
  ),
  HiddenTrigger(
    term: 'tentsuyu',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.1',
  ),
  HiddenTrigger(
    term: 'paella',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.2',
  ),
];

/// Hebrew hidden sources of fish (11 §8.1, §8.2, 12 §1.7).
const List<HiddenTrigger> _fishHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'רוטב דגים',
    certainty: TriggerCertainty.likely,
    source: '12 §1.7',
  ),
  HiddenTrigger(
    term: 'סורימי',
    certainty: TriggerCertainty.likely,
    source: '12 §1.7',
  ),
  HiddenTrigger(
    term: 'סלט קיסר',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'רוטב קיסר',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'וורסטרשייר',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'ווסטרשייר',
    certainty: TriggerCertainty.likely,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'דאשי',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.1',
  ),
  HiddenTrigger(
    term: 'מרק מיסו',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.1',
  ),
  HiddenTrigger(
    term: "קימצ'י",
    certainty: TriggerCertainty.suspected,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'רוטב ברביקיו',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.2',
  ),
  HiddenTrigger(
    term: 'טנצוי',
    certainty: TriggerCertainty.suspected,
    source: '11 §8.1',
  ),
  HiddenTrigger(
    term: 'פאייה',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.2',
  ),
];

/// The shrimp pastes (11 §9.1): the head of [_crustaceansHiddenEn], public
/// for the kosher vocabulary.
const List<HiddenTrigger> shrimpPastesEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'shrimp paste',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.1',
  ),
  HiddenTrigger(
    term: 'belacan',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.1',
  ),
  HiddenTrigger(
    term: 'kapi',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.1',
  ),
];

/// English hidden sources of crustaceans (11 §9.1, §9.2).
const List<HiddenTrigger> _crustaceansHiddenEn = <HiddenTrigger>[
  ...shrimpPastesEn,
  HiddenTrigger(
    term: 'paella',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.1',
  ),
  HiddenTrigger(
    term: 'curry paste',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.1',
  ),
  HiddenTrigger(
    term: 'surimi',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.2',
  ),
  HiddenTrigger(
    term: 'bouillabaisse',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.2',
  ),
  HiddenTrigger(
    term: 'fish stock',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.2',
  ),
  HiddenTrigger(
    term: 'fish sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.2',
  ),
  HiddenTrigger(
    term: 'massaman',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.1',
  ),
];

/// Hebrew hidden sources of crustaceans (12 §1.7).
const List<HiddenTrigger> _crustaceansHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'חריימה',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.7',
  ),
  HiddenTrigger(
    term: 'סורימי',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.7',
  ),
];

/// The mollusc sauces (11 §10.2): the head of [_molluscsHiddenEn], public
/// for the kosher vocabulary.
const List<HiddenTrigger> molluscSaucesEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'oyster sauce',
    certainty: TriggerCertainty.likely,
    source: '11 §10.2',
  ),
  HiddenTrigger(
    term: 'xo sauce',
    certainty: TriggerCertainty.likely,
    source: '11 §10.2',
  ),
];

/// English hidden sources of molluscs (11 §9.1, §10.2).
const List<HiddenTrigger> _molluscsHiddenEn = <HiddenTrigger>[
  ...molluscSaucesEn,
  HiddenTrigger(
    term: 'fish sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §10.2',
  ),
  HiddenTrigger(
    term: 'shrimp paste',
    certainty: TriggerCertainty.suspected,
    source: '11 §10.2',
  ),
  HiddenTrigger(
    term: 'paella',
    certainty: TriggerCertainty.suspected,
    source: '11 §9.1',
  ),
  HiddenTrigger(
    term: 'stir fry sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §10.2',
  ),
  HiddenTrigger(
    term: 'garlic sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §10.2',
  ),
  HiddenTrigger(
    term: 'garlic chili sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §10.2',
  ),
  HiddenTrigger(
    term: 'garlic and chili sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §10.2',
  ),
];

/// The mollusc sauces in Hebrew (12 §1.7): the head of
/// [_molluscsHiddenHe], public for the kosher vocabulary.
const List<HiddenTrigger> molluscSaucesHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'רוטב צדפות',
    certainty: TriggerCertainty.likely,
    source: '12 §1.7',
  ),
  HiddenTrigger(
    term: 'רוטב xo',
    certainty: TriggerCertainty.likely,
    source: '12 §1.7',
  ),
];

/// Hebrew hidden sources of molluscs (12 §1.7).
const List<HiddenTrigger> _molluscsHiddenHe = <HiddenTrigger>[
  ...molluscSaucesHe,
  HiddenTrigger(
    term: 'חריימה',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.7',
  ),
];

/// The crustacean term guards: "crab apple" is not a crab. Public for the
/// kosher vocabulary.
const Map<String, AllergenGuards> crustaceanTermGuards =
    <String, AllergenGuards>{
      'crab': AllergenGuards(afterEn: <String>['apple', 'apples']),
      'crabs': AllergenGuards(afterEn: <String>['apple', 'apples']),
    };

/// The mollusc term guards: an oyster mushroom is not an oyster. Public for
/// the kosher vocabulary.
const Map<String, AllergenGuards> molluscTermGuards = <String, AllergenGuards>{
  'oyster': AllergenGuards(afterEn: <String>['mushroom', 'mushrooms']),
  'oysters': AllergenGuards(afterEn: <String>['mushroom', 'mushrooms']),
};

/// Fish and seafood: one entry per restriction this group owns.
///
/// Guards are the negations, "vegan" and "free", plus the one guard the
/// documentation names for shellfish: a kosher menu serves none (12 §2.2).
/// A guard lowers a hit to `suspected` from the slot beside its term and
/// never cancels it (ALG-04a); "crab apple" and "oyster mushroom" are term
/// guards on the words they disarm.
/// "Vegetarian" is not a guard: it would lower "vegetarian and fish
/// options", and anchovy is routinely overlooked as "not meat" (11 §8.3).
const Map<RestrictionId, RestrictionVocabulary> seaVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.fish: RestrictionVocabulary(
        directEn: _fishEn,
        directHe: _fishHe,
        hiddenEn: _fishHiddenEn,
        hiddenHe: _fishHiddenHe,
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without', 'free of', 'free from', 'vegan'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי', 'נטול'],
          afterHe: <String>['טבעוני', 'טבעונית'],
        ),
        sources: <String>['11 §8.1', '11 §8.3', '12 §1.7'],
      ),
      RestrictionId.crustaceans: RestrictionVocabulary(
        directEn: _crustaceansEn,
        directHe: _crustaceansHe,
        hiddenEn: _crustaceansHiddenEn,
        hiddenHe: _crustaceansHiddenHe,
        guards: AllergenGuards(
          beforeEn: <String>[
            'no',
            'without',
            'free of',
            'free from',
            'vegan',
            'kosher',
          ],
          afterEn: <String>['free', 'kosher'],
          beforeHe: <String>['ללא', 'בלי', 'נטול', 'כשר', 'כשרה'],
          afterHe: <String>['כשר', 'כשרה', 'כשרים', 'טבעוני', 'טבעונית'],
        ),
        termGuards: crustaceanTermGuards,
        sources: <String>['11 §9.1', '11 §9.3', '12 §1.7', '12 §2.2'],
      ),
      RestrictionId.molluscs: RestrictionVocabulary(
        directEn: _molluscsEn,
        directHe: _molluscsHe,
        hiddenEn: _molluscsHiddenEn,
        hiddenHe: _molluscsHiddenHe,
        guards: AllergenGuards(
          beforeEn: <String>[
            'no',
            'without',
            'free of',
            'free from',
            'vegan',
            'kosher',
          ],
          afterEn: <String>['free', 'kosher'],
          beforeHe: <String>['ללא', 'בלי', 'נטול', 'כשר', 'כשרה'],
          afterHe: <String>['כשר', 'כשרה', 'כשרים', 'טבעוני', 'טבעונית'],
        ),
        termGuards: molluscTermGuards,
        sources: <String>['11 §10.1', '11 §10.3', '12 §1.7', '12 §2.2'],
      ),
    };
