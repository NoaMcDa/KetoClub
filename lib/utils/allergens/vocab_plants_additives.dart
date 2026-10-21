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
/// a guard lowers a hit to `suspected` (never cancels it) and counts only
/// in the slot beside its term (ALG-04a), so "no added" is a guard phrase
/// of its own; a coffee, cocoa or jelly bean is a term guard on "bean";
/// the Hebrew
/// boundary (`hebrewTriggerPattern`) allows a one-or-two-letter prefix on
/// the left and no suffix on the right, so `טירמיסו` does not contain
/// `מיסו` and `ליצירת` does not contain `ציר`; `פול` is listed without a
/// prefix because `כפול` ("double") would otherwise read as a fava bean,
/// and its genuine prefixed forms are terms of their own; `יין` likewise
/// ("wine" against `מיין`, "sorts"). The keto normaliser deletes the
/// Hebrew maqaf (it lies in the niqqud range), but the allergen matcher
/// reads it as a space in the text and in every term (ALG-04a), so a
/// compound written with one ("סויה־דבש") matches the spaced spelling.
///
/// `legumes` carries every direct term of `soy`, `peanuts` and `lupin`
/// and every hidden source of the three, because a peanut, a soybean and a
/// lupin are legumes (the corpus invariant `legumes >= max(peanuts, soy,
/// lupin)`). It carries every word of the single legumes too (chickpea,
/// lentil, pea, fenugreek, fava), spread from `vocab_legume_parts.dart`,
/// where its own chickpea-to-fenugreek words now live in the order it
/// listed them.
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocab_gluten_grains.dart';
import 'package:ketoclub/utils/allergens/vocab_legume_parts.dart';
import 'package:ketoclub/utils/allergens/vocab_nuts_seeds.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// Soy's direct English triggers, shared with `legumes` (soy is a legume).
/// Public because the diets that leave out soy (`vocab_diets_extra.dart`)
/// spread it.
const List<String> soyDirectEn = <String>[
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

/// Soy's direct Hebrew triggers, shared with `legumes` and spread like
/// [soyDirectEn].
const List<String> soyDirectHe = <String>[
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
  'סויה־דבש',
];

/// Soy's hidden English sources, shared with `legumes`.
const List<HiddenTrigger> _soyHiddenEn = <HiddenTrigger>[
  // Beyond Meat is made of pea and soy protein (12 §1.11, 11 §16.2).
  HiddenTrigger(
    term: 'beyond meat',
    certainty: TriggerCertainty.likely,
    source: '12 §1.11',
  ),
  HiddenTrigger(
    term: 'beyond burger',
    certainty: TriggerCertainty.likely,
    source: '12 §1.11',
  ),
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
    term: 'unagi',
    certainty: TriggerCertainty.likely,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'tentsuyu',
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
    term: 'sushi',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'sashimi',
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
  // Recall-gate additions (issue #352): the Asian, baked and
  // processed-meat carriers FARE names for soy (11 §6.2).
  HiddenTrigger(
    term: 'oyster sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'chow mein',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'sausage',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'sausages',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'bread',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'garlic sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'garlic chili sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'garlic and chili sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'wakame',
    certainty: TriggerCertainty.suspected,
    source: '12 §5',
  ),
  HiddenTrigger(
    term: 'chocolate',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.1',
  ),
  // Leftover recall misses (issue #352): the sesame sauce of Asian cold
  // noodles and a sweet wing glaze, which FARE's "sauces" and "Asian
  // cuisine" rows cover (11 §6.2). `peanut sauce` is a legumes term
  // already.
  HiddenTrigger(
    term: 'sesame sauce',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'sesame noodles',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'sweet glaze',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
];

/// Soy's hidden Hebrew sources, shared with `legumes`.
const List<HiddenTrigger> _soyHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'ביונד מיט',
    certainty: TriggerCertainty.likely,
    source: '12 §1.11',
  ),
  HiddenTrigger(
    term: 'ביונד בורגר',
    certainty: TriggerCertainty.likely,
    source: '12 §1.11',
  ),
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
    term: 'אונאגי',
    certainty: TriggerCertainty.likely,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'טנצוי',
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
    term: 'סושי',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'סשימי',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
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
  // Recall-gate additions (issue #352); see _soyHiddenEn.
  HiddenTrigger(
    term: 'רוטב צדפות',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'צ׳או מיין',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'נקניק',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'נקניקים',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'נקניקיה',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'נקניקיות',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'וואקמה',
    certainty: TriggerCertainty.suspected,
    source: '12 §5',
  ),
  HiddenTrigger(
    term: 'שוקולד',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.1',
  ),
  // Leftover recall misses (issue #352); see _soyHiddenEn.
  HiddenTrigger(
    term: 'רוטב מתקתק',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
  HiddenTrigger(
    term: 'רוטב שומשום',
    certainty: TriggerCertainty.suspected,
    source: '11 §6.2',
  ),
];

/// Legume-only English spellings for peanut and lupin dishes that the
/// sibling groups do not list as direct triggers. `legumes` spreads the
/// sibling lists ([peanutDirectEn], [lupinDirectEn]) and these, so it
/// carries every peanut and lupin spelling (a test compares them).
const List<String> peanutLupinExtraEn = <String>[
  'peanut butter',
  'peanut flour',
  'peanut oil',
  'peanut sauce',
  'arachis oil',
  // "satay" is a hidden peanut source, which `legumes` spreads too.
  'sate',
  'lupini beans',
  'lupin flour',
  'lupin protein',
];

/// The words that make "bean" another food: a coffee, vanilla or cocoa
/// bean, a jelly bean.
const List<String> _notLegumeBeansEn = <String>[
  'coffee',
  'vanilla',
  'cocoa',
  'cacao',
  'jelly',
];

/// The English legume words beyond soy, peanut and lupin, before the peas
/// (11 §16.1): the family, chickpeas and hummus, falafel, lentils and dal.
/// Public, with [peaFoodsEn] and [beanFoodsEn], because the diets that
/// leave out legumes (`vocab_diets_extra.dart`) spread them, and Whole30
/// allows peas.
const List<String> pulseFoodsEn = <String>[
  'legume',
  'legumes',
  'pulses',
  ...chickpeaDirectEn,
  'falafel',
  ...lentilDirectEn,
  ...dalEn,
  ...mujadaraEn,
];

/// The English pea words of `legumes` (11 §16.1); see [pulseFoodsEn].
const List<String> peaFoodsEn = <String>[...peaDirectEn];

/// The English bean words of `legumes` after the peas (11 §16.1): fava,
/// the beans and fenugreek; see [pulseFoodsEn].
const List<String> beanFoodsEn = <String>[
  ...favaDirectEn,
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
  ...fenugreekDirectEn,
];

/// [pulseFoodsEn] in Hebrew (11 §16.1, 12 §1.3).
const List<String> pulseFoodsHe = <String>[
  'קטניות',
  'קטנית',
  ...chickpeaDirectHe,
  'פלאפל',
  ...mujadaraHe,
  ...mashawshaHe,
  ...lentilDirectHe,
];

/// [peaFoodsEn] in Hebrew.
const List<String> peaFoodsHe = <String>[...peaDirectHe];

/// [beanFoodsEn] in Hebrew. `פול` is compiled with no permissive prefix
/// (`כפול` is "double") wherever it is spread.
const List<String> beanFoodsHe = <String>[
  ...favaDirectHe,
  'שעועית',
  ...fenugreekDirectHe,
];

/// Every direct English trigger of `legumes`: soy, peanut and lupin and
/// the other legumes. Public because the diets that leave out every legume
/// (paleo, AIP) spread it.
const List<String> legumesDirectEn = <String>[
  ...soyDirectEn,
  ...peanutDirectEn,
  ...lupinDirectEn,
  ...peanutLupinExtraEn,
  ...pulseFoodsEn,
  ...peaFoodsEn,
  ...beanFoodsEn,
  // The single legumes' own words (`vocab_legume_parts.dart`), after
  // every word `legumes` had before they were split out.
  ...chickpeaExtraEn,
  ...lentilExtraEn,
  ...peaExtraEn,
  ...fenugreekExtraEn,
  ...favaExtraEn,
];

/// [legumesDirectEn] in Hebrew.
const List<String> legumesDirectHe = <String>[
  ...soyDirectHe,
  ...peanutDirectHe,
  ...lupinDirectHe,
  ...pulseFoodsHe,
  ...peaFoodsHe,
  ...beanFoodsHe,
  ...chickpeaExtraHe,
  ...lentilExtraHe,
  ...fenugreekExtraHe,
];

/// Plants and additives: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> plantsAdditivesVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.soy: RestrictionVocabulary(
        directEn: <String>[...soyDirectEn],
        directHe: <String>[...soyDirectHe],
        hiddenEn: <HiddenTrigger>[
          ..._soyHiddenEn,
          // The Asian dishes below are not in the shared list: `legumes`
          // already carries them through the peanut and lupin lists, and a
          // term may not be listed twice (issue #352).
          HiddenTrigger(
            term: 'satay',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'stir fry',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'spring roll',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'spring rolls',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'rolls',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          ..._soyHiddenHe,
          // Bamba lists soy (12 §1.2). Not in the shared list: `legumes`
          // already has it as a direct peanut term.
          HiddenTrigger(
            term: 'במבה',
            certainty: TriggerCertainty.likely,
            source: '12 §1.2',
          ),
          // Not in the shared list, as for the English ones above.
          HiddenTrigger(
            term: 'סאטה',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'ספרינג רול',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
          HiddenTrigger(
            term: 'אגרול',
            certainty: TriggerCertainty.suspected,
            source: '11 §6.2',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי', 'נטול', 'נטולת'],
        ),
        sources: <String>[
          '11 §6.1',
          '11 §6.2',
          '11 §6.3',
          '12 §1.11',
          '12 §1.2',
        ],
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
            term: 'soup',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'soups',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'soup base',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'stew',
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
            term: 'risotto',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'bolognese',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.1',
          ),
          HiddenTrigger(
            term: 'ragu',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.1',
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
          HiddenTrigger(
            term: 'chowder',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'bisque',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'ציר',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'מרק',
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
            term: 'ריזוטו',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
          HiddenTrigger(
            term: 'בולונז',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.1',
          ),
          HiddenTrigger(
            term: 'ראגו',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.1',
          ),
          HiddenTrigger(
            term: 'וולדורף',
            certainty: TriggerCertainty.likely,
            source: '12 §1.9',
          ),
          HiddenTrigger(
            term: 'צ׳אודר',
            certainty: TriggerCertainty.suspected,
            source: '11 §12.2',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי', 'נטול', 'נטולת'],
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
          'חרדל־דבש',
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
            certainty: TriggerCertainty.likely,
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
            term: 'caesar salad',
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
          // Recall-gate additions (issue #352): the creamy dressings
          // and sauces Health Canada names (11 §13.2).
          HiddenTrigger(
            term: 'ranch',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'ranch dressing',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'blue cheese dressing',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'coleslaw',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'tartar sauce',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'tartare sauce',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'tartar',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'tartare',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          // Leftover recall misses (issue #352): a sauce the menu will
          // not name ("house dressing" is the term Allergy UK says to
          // refuse without ingredients) and a sweet meat glaze (11 §13.2).
          HiddenTrigger(
            term: 'house sauce',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'secret sauce',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'sweet glaze',
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
            certainty: TriggerCertainty.likely,
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
            term: 'סלט קיסר',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.8',
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
          HiddenTrigger(
            term: 'כבוש',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'כבושה',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'כבושים',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'כבושות',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'רוטב טרטר',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'טרטר',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'קולסלו',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          // Leftover recall misses (issue #352): the pickled forms that
          // are not כבוש ("חלפיניו מוחמץ"), a sauce the menu will not name
          // and a sweet meat glaze (11 §13.2).
          HiddenTrigger(
            term: 'מוחמץ',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'מוחמצת',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'מוחמצים',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'מוחמצות',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'רוטב הבית',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'רוטב סודי',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
          HiddenTrigger(
            term: 'רוטב מתקתק',
            certainty: TriggerCertainty.suspected,
            source: '11 §13.2',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without'],
          afterEn: <String>['free'],
          beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי', 'נטול', 'נטולת'],
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
            term: 'currants',
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
            term: 'fruit juice',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'fruit juices',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'cordial',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'guacamole',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'soft drink',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'soft drinks',
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
          HiddenTrigger(
            term: 'mustard',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'salad dressing',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'sausage',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'sausages',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'burger',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'burgers',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          // Recall-gate additions (issue #352): condiments, sushi rice
          // and beer brands (11 §15.2).
          HiddenTrigger(
            term: 'ketchup',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'catsup',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'bbq sauce',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'barbecue sauce',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'vinaigrette',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'sushi',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          // Leftover recall misses (issue #352): sushi named by its roll,
          // whose rice is seasoned with vinegar (11 §15.2).
          HiddenTrigger(
            term: 'maki',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'uramaki',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'nigiri',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'inside out roll',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'goldstar',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'san miguel',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'heineken',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'tuborg',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'carlsberg',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'guinness',
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
            term: 'מיץ פירות',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'גוואקמולי',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'גואקמולי',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
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
          HiddenTrigger(
            term: 'חרדל',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'נקניק',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'נקניקיות',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'המבורגר',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'קטשופ',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'רוטב ברביקיו',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'ויניגרט',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'כבוש',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'כבושה',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'כבושים',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'כבושות',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'סושי',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          // Leftover recall misses (issue #352); see the English rolls.
          HiddenTrigger(
            term: 'מאקי',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'ניגירי',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'אינסייד אאוט',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'גולדסטאר',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'סאן מיגל',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'היינקן',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'טובורג',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'קרלסברג',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'גינס',
            certainty: TriggerCertainty.suspected,
            source: '11 §15.2',
          ),
          HiddenTrigger(
            term: 'פריגת ענבים',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.10',
          ),
        ],
        guards: AllergenGuards(
          beforeEn: <String>['no', 'without', 'no added', 'without added'],
          afterEn: <String>['free'],
          beforeHe: <String>[
            'ללא',
            'וללא',
            'בלי',
            'ובלי',
            'נטול',
            'נטולת',
            'ללא תוספת',
            'בלי תוספת',
          ],
        ),
        noPrefixHe: <String>['יין'],
        sources: <String>['11 §15.1', '11 §15.2', '11 §15.3', '12 §1.10'],
      ),
      RestrictionId.legumes: RestrictionVocabulary(
        directEn: legumesDirectEn,
        directHe: legumesDirectHe,
        hiddenEn: <HiddenTrigger>[
          ..._soyHiddenEn,
          ...peanutHiddenEn,
          ...lupinHiddenEn,
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
          ...legumePartsHiddenEn,
        ],
        hiddenHe: <HiddenTrigger>[
          ..._soyHiddenHe,
          ...peanutHiddenHe,
          ...lupinHiddenHe,
          HiddenTrigger(
            term: 'סביח',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.3',
          ),
          ...legumePartsHiddenHe,
        ],
        guards: legumeGuards,
        // A coffee, vanilla or cocoa bean and a jelly bean are no legume
        // (ALG-04a): term guards on "bean", not restriction-wide.
        termGuards: <String, AllergenGuards>{
          'bean': AllergenGuards(beforeEn: _notLegumeBeansEn),
          'beans': AllergenGuards(beforeEn: _notLegumeBeansEn),
        },
        noPrefixHe: <String>['פול'],
        sources: <String>[
          '11 §16.1',
          '11 §16.2',
          '11 §16.3',
          '12 §1.3',
          '11 §1.1',
          '11 §14.1',
          '11 §28',
          '12 §12',
        ],
      ),
    };
