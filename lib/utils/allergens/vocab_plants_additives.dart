/// Plants and additives: the trigger vocabulary of soy, celery, mustard,
/// sulphites and legumes (Banto; ALG-01, issue #343).
///
/// Every term comes from
/// `allergen app documentation/11_hidden_allergen_sources.md` or
/// `12_israeli_and_us_menu_lexicon.md` and its source cites the section
/// (`"11 §11"`, `"12 §1.1"`), which
/// `test/utils/allergens/vocabulary_test.dart` checks. After a change,
/// regenerate the goldens and copy `allergens.json` to
/// `backend/app/keto/` (architecture.md D26).
///
/// Desk research, not clinical review: the sections are unreviewed, and so
/// is every certainty below. Allergens here are strict: this file favours
/// recall, so a hidden source is listed even when only some kitchens use
/// it, and its certainty says how often.
///
/// Matcher facts the lists are written around (`allergen_matcher.dart`):
/// a guard counts only within two words of the trigger; the Hebrew
/// boundary (`hebrewTriggerPattern`) allows a one-or-two-letter prefix on
/// the left and no suffix on the right, so `טירמיסו` does not contain
/// `מיסו` and `ליצירת` does not contain `ציר`; `פול` is listed without a
/// prefix because `כפול` ("double") would otherwise read as a fava bean,
/// and its genuine prefixed forms are terms of their own; `יין` likewise
/// ("wine" against `מיין`, "sorts").
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// Soy's direct English triggers, shared with `legumes` (soy is a legume).
const List<String> _soyDirectEn = <String>[
  'soy',
  'soya',
  'soybean',
  'soybeans',
  'soy bean',
  'soy beans',
  'edamame',
  'tofu',
  'bean curd',
  'tempeh',
  'miso',
  'natto',
  'shoyu',
  'tamari',
  'soy sauce',
  'soy milk',
  'soy protein',
  'soy flour',
  'yuba',
  'textured vegetable protein',
  'tvp',
];

/// Soy's direct Hebrew triggers, shared with `legumes`.
const List<String> _soyDirectHe = <String>[
  'סויה',
  'סוייה',
  'פולי סויה',
  'טופו',
  'אדממה',
  'אדמאמה',
  'מיסו',
  'טמפה',
  'נאטו',
  'שויו',
  'טמרי',
  'רוטב סויה',
  'חלב סויה',
  'חלבון סויה',
  'קמח סויה',
];

/// Peanut's direct English triggers: a peanut is a legume, so `legumes`
/// carries every spelling the peanut vocabulary does (a test compares them).
const List<String> _peanutDirectEn = <String>[
  'peanut',
  'peanuts',
  'peanut butter',
  'peanut flour',
  'peanut oil',
  'peanut sauce',
  'arachis oil',
  'groundnut',
  'groundnuts',
  'monkey nut',
  'satay',
  'sate',
];

/// Peanut's direct Hebrew triggers; see `_peanutDirectEn`.
const List<String> _peanutDirectHe = <String>['בוטנים', 'בוטן', 'אגוזי אדמה'];

/// Lupin's direct English triggers; see `_peanutDirectEn`.
const List<String> _lupinDirectEn = <String>[
  'lupin',
  'lupine',
  'lupins',
  'lupini',
  'lupini beans',
  'lupin flour',
  'lupin protein',
];

/// Lupin's direct Hebrew triggers; see `_peanutDirectEn`.
const List<String> _lupinDirectHe = <String>['תורמוס', 'לופין'];

/// Plants and additives: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> plantsAdditivesVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.soy: RestrictionVocabulary(
        directEn: <String>[..._soyDirectEn],
        directHe: <String>[..._soyDirectHe],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'teriyaki',
            certainty: TriggerCertainty.likely,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'hoisin',
            certainty: TriggerCertainty.likely,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'ponzu',
            certainty: TriggerCertainty.likely,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'lecithin',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'E322',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'margarine',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'vegetable protein',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'hydrolyzed vegetable protein',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'hydrolysed vegetable protein',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'hydrolyzed plant protein',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'vegetable broth',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'vegan sausage',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'vegan sausages',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'vegan burger',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'vegan nuggets',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'vegan schnitzel',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'vegan meat',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'plant based meat',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'plant based burger',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'meat alternative',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'meat substitute',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'טריאקי',
            certainty: TriggerCertainty.likely,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'הויסין',
            certainty: TriggerCertainty.likely,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'פונזו',
            certainty: TriggerCertainty.likely,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'לציטין',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'מרגרינה',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'חלבון צמחי',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'נקניקיות טבעוניות',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'נקניק טבעוני',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'שניצל טבעוני',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'שניצל תירס',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'קציצות טבעוניות',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'המבורגר טבעוני',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'בשר טבעוני',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
          HiddenTrigger(
            term: 'תחליף בשר',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.11',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי', 'נטול', 'נטולת'],
        ),
        sources: <String>['11 §6.1', '11 §6.2', '11 §6.3', '12 §1.11'],
      ),
      RestrictionId.celery: RestrictionVocabulary(
        directEn: <String>[
          'celery',
          'celeriac',
          'celery salt',
          'celery seed',
          'celery seeds',
          'celery root',
          'celery juice',
          'celery leaves',
          'celery stalks',
        ],
        directHe: <String>[
          'סלרי',
          'שורש סלרי',
          'סלרי שורש',
          'מלח סלרי',
          'זרעי סלרי',
          'מיץ סלרי',
          'עלי סלרי',
          'כרפס',
        ],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'stock',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'broth',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'bouillon',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'stock cube',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'soup base',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'consomme',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'gravy',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'waldorf',
            certainty: TriggerCertainty.likely,
            source: '11 §12.1',
          ),
          HiddenTrigger(
            term: 'mirepoix',
            certainty: TriggerCertainty.likely,
            source: '11 §12.1',
          ),
          HiddenTrigger(
            term: 'soffritto',
            certainty: TriggerCertainty.likely,
            source: '11 §12.1',
          ),
          HiddenTrigger(
            term: 'bloody mary',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.1',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'ציר',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'מרק ירקות',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'מרק עוף',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'בסיס מרק',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'אבקת מרק',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'קובית מרק',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'קוביות מרק',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'וולדורף',
            certainty: TriggerCertainty.likely,
            source: '12 §1.9',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי', 'נטול', 'נטולת'],
        ),
        sources: <String>['11 §12.1', '11 §12.2', '11 §12.3', '12 §1.9'],
      ),
      RestrictionId.mustard: RestrictionVocabulary(
        directEn: <String>[
          'mustard',
          'dijon',
          'wholegrain mustard',
          'whole grain mustard',
          'mustard seed',
          'mustard seeds',
          'mustard powder',
          'mustard oil',
          'mustard greens',
          'mustard leaves',
          'mustard cress',
          'honey mustard',
          'english mustard',
          'piccalilli',
        ],
        directHe: <String>[
          'חרדל',
          "חרדל דיז'ון",
          "דיז'ון",
          'חרדל דבש',
          'זרעי חרדל',
          'אבקת חרדל',
          'עלי חרדל',
        ],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'mayonnaise',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'mayo',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'aioli',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'pickle',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'pickles',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'pickled',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'gherkin',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'gherkins',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'vinaigrette',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'salad dressing',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'house dressing',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'caesar dressing',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'curry',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'curry paste',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'curry powder',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'chutney',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'marinade',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'potato salad',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'bbq sauce',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'barbecue sauce',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'מיונז',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'איולי',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'חמוצים',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'מלפפון חמוץ',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'מלפפונים חמוצים',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'ויניגרט',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'קארי',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'ממרח קארי',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'פסטת קארי',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'מרינדה',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'סלט תפוחי אדמה',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'רוטב קיסר',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
          ),
          HiddenTrigger(
            term: 'רוטב ברביקיו',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'ברביקיו',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי', 'נטול', 'נטולת'],
        ),
        sources: <String>['11 §13.1', '11 §13.2', '11 §13.3', '12 §1.8'],
      ),
      RestrictionId.sulphites: RestrictionVocabulary(
        directEn: <String>[
          'sulphite',
          'sulphites',
          'sulfite',
          'sulfites',
          'sulphur dioxide',
          'sulfur dioxide',
          'bisulphite',
          'bisulfite',
          'metabisulphite',
          'metabisulfite',
          'sodium metabisulphite',
          'sodium metabisulfite',
          'potassium metabisulphite',
          'potassium metabisulfite',
          'E220',
          'E221',
          'E222',
          'E223',
          'E224',
          'E225',
          'E226',
          'E227',
          'E228',
        ],
        directHe: <String>[
          'סולפיט',
          'סולפיטים',
          'גופרית דו חמצנית',
          'דו תחמוצת הגופרית',
        ],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'wine',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'wines',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'champagne',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'prosecco',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'sherry',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'marsala',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'vinegar',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'balsamic',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'dried fruit',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'dried fruits',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'dried apricot',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'dried apricots',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'dried cranberries',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'dried figs',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'dried mango',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'dried vegetables',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'raisin',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'raisins',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'sultanas',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'prunes',
            certainty: TriggerCertainty.likely,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'pickles',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'pickled',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'shrimp',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'shrimps',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'prawn',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'prawns',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'chips',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'fries',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'french fries',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'grape juice',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'beer',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'cider',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'יין',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'ביין',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'ויין',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'היין',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'וביין',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'יינות',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'פירות יבשים',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'פירות מיובשים',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'משמש מיובש',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'משמשים מיובשים',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'משמש יבש',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'משמשים יבשים',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'צימוקים',
            certainty: TriggerCertainty.likely,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'חמוציות',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'חרוסת',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'חמוצים',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'חומץ',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'מיץ ענבים',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.10',
          ),
          HiddenTrigger(
            term: 'בירה',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'סיידר',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'שרימפס',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: "צ'יפס",
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי', 'נטול', 'נטולת'],
        ),
        noPrefixHe: <String>['יין'],
        sources: <String>['11 §15.1', '11 §15.2', '11 §15.3', '12 §1.10'],
      ),
      RestrictionId.legumes: RestrictionVocabulary(
        directEn: <String>[
          ..._soyDirectEn,
          ..._peanutDirectEn,
          ..._lupinDirectEn,
          'legume',
          'legumes',
          'pulses',
          'chickpea',
          'chickpeas',
          'chick pea',
          'chick peas',
          'garbanzo',
          'garbanzos',
          'hummus',
          'houmous',
          'humus',
          'falafel',
          'lentil',
          'lentils',
          'dal',
          'dhal',
          'dahl',
          'majadra',
          'mujadara',
          'mejadra',
          'pea',
          'peas',
          'split pea',
          'split peas',
          'green pea',
          'green peas',
          'pea protein',
          'fava',
          'fava beans',
          'broad bean',
          'broad beans',
          'ful medames',
          'bean',
          'beans',
          'black beans',
          'kidney beans',
          'cannellini',
          'haricot',
          'mung bean',
          'mung beans',
          'adzuki',
          'cowpea',
          'black eyed peas',
          'fenugreek',
        ],
        directHe: <String>[
          ..._soyDirectHe,
          ..._peanutDirectHe,
          ..._lupinDirectHe,
          'קטניות',
          'קטנית',
          'חומוס',
          'הומוס',
          'גרגירי חומוס',
          'חימצה',
          'פלאפל',
          "מג'דרה",
          "מוג'דרה",
          'משאוושה',
          'עדשים',
          'עדשה',
          'אפונה',
          'פול',
          'פולים',
          'הפול',
          'בפול',
          'ופול',
          'שעועית',
          'חילבה',
        ],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'vegetable protein',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.3',
          ),
          HiddenTrigger(
            term: 'veggie burger',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'veggie burgers',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'vegan burger',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'vegan sausage',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'vegan sausages',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'plant based burger',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'plant based meat',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'gram flour',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'besan',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'pakora',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'socca',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'sabich',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.3',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'חלבון צמחי',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.3',
          ),
          HiddenTrigger(
            term: 'המבורגר טבעוני',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'נקניקיות טבעוניות',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'שניצל טבעוני',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'קציצות טבעוניות',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'בשר טבעוני',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'תחליף בשר',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'סביח',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.3',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>[
            'no',
            'without',
            'coffee',
            'vanilla',
            'cocoa',
            'cacao',
            'jelly',
          ],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'בלי', 'נטול', 'נטולת'],
        ),
        noPrefixHe: <String>['פול'],
        sources: <String>[
          '11 §16.1',
          '11 §16.2',
          '11 §16.3',
          '12 §1.3',
          '11 §1.1',
          '11 §14.1',
        ],
      ),
    };
