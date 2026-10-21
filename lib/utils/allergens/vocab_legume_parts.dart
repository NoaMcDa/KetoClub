/// Legume parts: the trigger vocabulary of each legume as its own toggle
/// under legumes — chickpea, lentil, pea and fenugreek — and of fava beans
/// for G6PD deficiency (Banto; issue #342).
///
/// Sources: file 11 §16 (the legumes parent: direct triggers, pea protein
/// in plant-based meat, "model each legume as its own toggle under a
/// 'legumes' parent", favism is not an allergy) and §28 (this file's own
/// section: what each single legume hides in, checked 2026-10-21 against
/// web search results), file 12 §1.3 (the Israeli legume dishes) and §12
/// (the Hebrew spellings, and the words a Hebrew term must not match).
///
/// Desk research, not clinical review: the sections are unreviewed, and so
/// is every certainty below. Every restriction here is strict (fava is
/// `medical`, the rest are allergens), so the lists favour recall.
///
/// **One list, two vocabularies.** Before this file was filled, `legumes`
/// (`vocab_plants_additives.dart`) already carried most of these words.
/// The public lists below are those words, cut out of `legumes` in the
/// order it listed them, so `legumes` spreads them back and its golden
/// output only grows; the `...Extra...` lists are the words this file
/// adds, which `legumes` spreads too. So `legumes` stays a superset of
/// every single legume (a test checks it), and a term is written once.
/// A term whose certainty differs between the two is written in each:
/// "falafel" is stated for `legumes` (it is chickpea *or* fava, a legume
/// either way) but likely for chickpea and suspected for fava; "dal" is a
/// split pulse, so stated for `legumes` and likely for lentil; gram flour
/// is chickpea flour, so stated for chickpea, where `legumes` has kept it
/// a hidden source.
///
/// Matcher facts the lists are written around (`allergen_matcher.dart`):
/// English terms match on the ASCII word boundary, so "pea" is never
/// found inside "chickpea", "peanut" or "peach", but it is found in "chick
/// peas" and "black-eyed peas": a term guard lowers those to suspected
/// (a guard never cancels). `פול` takes no prefix, because `כפול`
/// ("double") would read as a fava bean, and its genuine prefixed forms are
/// terms of their own; nothing here lists `פולי`, which is the construct
/// of soybeans, coffee beans and cocoa beans (`פולי סויה`). Fenugreek is
/// `חילבה`, never `חלבה` (halva, a sesame sweet; file 12 §1.1).
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// Chickpea's direct English words, as `legumes` lists them.
const List<String> chickpeaDirectEn = <String>[
  'chickpea',
  'chickpeas',
  'chick pea',
  'chick peas',
  'garbanzo',
  'garbanzos',
  'hummus',
  'houmous',
  'humus',
];

/// Lentil's direct English words, as `legumes` lists them.
const List<String> lentilDirectEn = <String>['lentil', 'lentils'];

/// Dal, a split pulse: stated for `legumes`, likely for lentil (dal is
/// lentils, peas or beans; file 11 §28.2).
const List<String> dalEn = <String>['dal', 'dhal', 'dahl'];

/// Mujadara, rice or bulgur with lentils, as `legumes` spells it.
const List<String> mujadaraEn = <String>['majadra', 'mujadara', 'mejadra'];

/// Pea's direct English words, as `legumes` lists them.
const List<String> peaDirectEn = <String>[
  'pea',
  'peas',
  'split pea',
  'split peas',
  'green pea',
  'green peas',
  'pea protein',
];

/// Fava's direct English words, as `legumes` lists them.
const List<String> favaDirectEn = <String>[
  'fava',
  'fava beans',
  'broad bean',
  'broad beans',
  'ful medames',
];

/// Fenugreek's direct English word, as `legumes` lists it.
const List<String> fenugreekDirectEn = <String>['fenugreek'];

/// Chickpea's direct Hebrew words, as `legumes` lists them.
const List<String> chickpeaDirectHe = <String>[
  'חומוס',
  'הומוס',
  'גרגירי חומוס',
  'חימצה',
];

/// Mujadara in Hebrew, as `legumes` spells it.
const List<String> mujadaraHe = <String>["מג'דרה", "מוג'דרה"];

/// Mashawsha, the Galilean masabacha of whole chickpeas (file 12 §12.1),
/// as `legumes` lists it.
const List<String> mashawshaHe = <String>['משאוושה'];

/// Lentil's direct Hebrew words, as `legumes` lists them.
const List<String> lentilDirectHe = <String>['עדשים', 'עדשה'];

/// Pea's direct Hebrew word, as `legumes` lists it.
const List<String> peaDirectHe = <String>['אפונה'];

/// Fava's direct Hebrew words, as `legumes` lists them: `פול` takes no
/// prefix, so its prefixed forms are listed.
const List<String> favaDirectHe = <String>[
  'פול',
  'פולים',
  'הפול',
  'בפול',
  'ופול',
];

/// Fenugreek's direct Hebrew word, as `legumes` lists it.
const List<String> fenugreekDirectHe = <String>['חילבה'];

/// The direct English words this file adds, one list per legume, which
/// `legumes` spreads after its own (file 11 §28).
const List<String> chickpeaExtraEn = <String>[
  'hommus',
  'chana',
  'channa',
  'chole',
  'msabbaha',
  'masabacha',
];

/// See [chickpeaExtraEn].
const List<String> lentilExtraEn = <String>[
  'mujaddara',
  'mujadra',
  'masoor',
  'mercimek',
];

/// See [chickpeaExtraEn]. "Snow peas", "snap peas" and "mushy peas" are
/// found through "peas" already.
const List<String> peaExtraEn = <String>[
  'petits pois',
  'petit pois',
  'mangetout',
  'sugar snap',
  'pease pudding',
  'matar',
];

/// See [chickpeaExtraEn].
const List<String> fenugreekExtraEn = <String>[
  'methi',
  'hilbe',
  'hilbeh',
  'helbeh',
  'helba',
  'hulba',
  'hulbah',
];

/// See [chickpeaExtraEn]. Not the bare "foul", an English word, nor
/// "fave", which a menu uses for "favourite".
const List<String> favaExtraEn = <String>[
  'faba',
  'ful',
  'foul medames',
  'ful mudammas',
  'foul mudammas',
  'fool medames',
  'horse bean',
  'horse beans',
];

/// The direct Hebrew words this file adds, which `legumes` spreads after
/// its own (file 12 §12).
const List<String> chickpeaExtraHe = <String>['גרגרי חומוס', 'מסבחה', 'מסבאחה'];

/// See [chickpeaExtraHe].
const List<String> lentilExtraHe = <String>["מג'אדרה"];

/// See [chickpeaExtraHe]: `גרגרנית` is the fenugreek genus, as in
/// `גרגרנית יוונית`.
const List<String> fenugreekExtraHe = <String>['גרגרנית'];

/// The hidden English sources this file adds that `legumes` did not have,
/// each at the certainty `legumes` gives it: the surest any single legume
/// gives it, except a plural that follows its singular's certainty in
/// `legumes` ("pakoras" as "pakora"). The single legumes write their own
/// entries, at their own certainty.
const List<HiddenTrigger> legumePartsHiddenEn = <HiddenTrigger>[
  HiddenTrigger(
    term: 'pakoras',
    certainty: TriggerCertainty.suspected,
    source: '11 §16.2',
  ),
  HiddenTrigger(
    term: 'bhaji',
    certainty: TriggerCertainty.likely,
    source: '11 §28.1',
  ),
  HiddenTrigger(
    term: 'bhajis',
    certainty: TriggerCertainty.likely,
    source: '11 §28.1',
  ),
  HiddenTrigger(
    term: 'farinata',
    certainty: TriggerCertainty.likely,
    source: '11 §28.1',
  ),
  HiddenTrigger(
    term: 'aquafaba',
    certainty: TriggerCertainty.likely,
    source: '11 §28.1',
  ),
  HiddenTrigger(
    term: 'harira',
    certainty: TriggerCertainty.likely,
    source: '11 §28.1',
  ),
  HiddenTrigger(
    term: 'koshari',
    certainty: TriggerCertainty.likely,
    source: '11 §28.2',
  ),
  HiddenTrigger(
    term: 'kushari',
    certainty: TriggerCertainty.likely,
    source: '11 §28.2',
  ),
  HiddenTrigger(
    term: 'daal',
    certainty: TriggerCertainty.likely,
    source: '11 §28.2',
  ),
  HiddenTrigger(
    term: 'samosa',
    certainty: TriggerCertainty.suspected,
    source: '11 §28.3',
  ),
  HiddenTrigger(
    term: 'samosas',
    certainty: TriggerCertainty.suspected,
    source: '11 §28.3',
  ),
  HiddenTrigger(
    term: 'santorini fava',
    certainty: TriggerCertainty.likely,
    source: '11 §28.3',
  ),
  HiddenTrigger(
    term: 'panch phoron',
    certainty: TriggerCertainty.likely,
    source: '11 §28.4',
  ),
  HiddenTrigger(
    term: 'saltah',
    certainty: TriggerCertainty.likely,
    source: '11 §28.4',
  ),
  HiddenTrigger(
    term: 'curry powder',
    certainty: TriggerCertainty.suspected,
    source: '11 §28.4',
  ),
  HiddenTrigger(
    term: 'hawaij',
    certainty: TriggerCertainty.suspected,
    source: '11 §28.4',
  ),
  HiddenTrigger(
    term: "ta'ameya",
    certainty: TriggerCertainty.likely,
    source: '11 §28.5',
  ),
  HiddenTrigger(
    term: 'tamiya',
    certainty: TriggerCertainty.likely,
    source: '11 §28.5',
  ),
  HiddenTrigger(
    term: 'bissara',
    certainty: TriggerCertainty.likely,
    source: '11 §28.5',
  ),
];

/// The hidden Hebrew sources this file adds that `legumes` did not have;
/// see [legumePartsHiddenEn].
const List<HiddenTrigger> legumePartsHiddenHe = <HiddenTrigger>[
  HiddenTrigger(
    term: 'סמוסה',
    certainty: TriggerCertainty.suspected,
    source: '12 §12.3',
  ),
  HiddenTrigger(
    term: 'מרק תימני',
    certainty: TriggerCertainty.suspected,
    source: '12 §1.3',
  ),
  HiddenTrigger(
    term: 'חוויג',
    certainty: TriggerCertainty.suspected,
    source: '12 §12.4',
  ),
  HiddenTrigger(
    term: 'חוואייג',
    certainty: TriggerCertainty.suspected,
    source: '12 §12.4',
  ),
  HiddenTrigger(
    term: 'אבקת קארי',
    certainty: TriggerCertainty.suspected,
    source: '12 §12.4',
  ),
];

/// The guards of every legume, `legumes` included: "no", "without",
/// "-free" and their Hebrew twins lower a trigger beside them (file 11
/// §16.3: no guard clears a legume).
const AllergenGuards legumeGuards = AllergenGuards(
  beforeEn: <String>['no', 'without'],
  afterEn: <String>['free'],
  beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי', 'נטול', 'נטולת'],
);

/// The words that make "pea" another legume: a chickpea written as two
/// words, a black-eyed pea, a pigeon pea, a butterfly pea (file 11 §28.3).
/// They lower the hit, never cancel it: these are legumes too.
const AllergenGuards _notGardenPea = AllergenGuards(
  beforeEn: <String>['chick', 'eyed', 'pigeon', 'butterfly'],
);

/// Legume parts: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> legumePartsVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.chickpea: RestrictionVocabulary(
        directEn: <String>[
          ...chickpeaDirectEn,
          ...chickpeaExtraEn,
          // Gram flour (besan) is milled chickpea (file 11 §28.1);
          // `legumes` keeps both as hidden sources (11 §16.2).
          'gram flour',
          'besan',
        ],
        directHe: <String>[
          ...chickpeaDirectHe,
          ...mashawshaHe,
          ...chickpeaExtraHe,
        ],
        hiddenEn: <HiddenTrigger>[
          // Israeli falafel is chickpea; Egyptian ta'ameya is fava, and
          // some falafel mixes the two (11 §28.1, 12 §1.3).
          HiddenTrigger(
            term: 'falafel',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          HiddenTrigger(
            term: 'pakora',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          HiddenTrigger(
            term: 'pakoras',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          HiddenTrigger(
            term: 'bhaji',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          HiddenTrigger(
            term: 'bhajis',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          HiddenTrigger(
            term: 'socca',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          HiddenTrigger(
            term: 'farinata',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          HiddenTrigger(
            term: 'aquafaba',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          HiddenTrigger(
            term: 'harira',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
          // Chickpeas are optional in koshari (11 §28.2).
          HiddenTrigger(
            term: 'koshari',
            certainty: TriggerCertainty.suspected,
            source: '11 §28.2',
          ),
          HiddenTrigger(
            term: 'kushari',
            certainty: TriggerCertainty.suspected,
            source: '11 §28.2',
          ),
          HiddenTrigger(
            term: 'sabich',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.3',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'פלאפל',
            certainty: TriggerCertainty.likely,
            source: '12 §1.3',
          ),
          HiddenTrigger(
            term: 'סביח',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.3',
          ),
        ],
        guards: legumeGuards,
        sources: <String>['11 §16.1', '11 §28.1', '12 §1.3', '12 §12.1'],
      ),
      RestrictionId.lentil: RestrictionVocabulary(
        directEn: <String>[...lentilDirectEn, ...mujadaraEn, ...lentilExtraEn],
        directHe: <String>[...mujadaraHe, ...lentilDirectHe, ...lentilExtraHe],
        hiddenEn: <HiddenTrigger>[
          // Dal is any split pulse: lentils, peas or beans (11 §28.2).
          HiddenTrigger(
            term: 'dal',
            certainty: TriggerCertainty.likely,
            source: '11 §28.2',
          ),
          HiddenTrigger(
            term: 'dhal',
            certainty: TriggerCertainty.likely,
            source: '11 §28.2',
          ),
          HiddenTrigger(
            term: 'dahl',
            certainty: TriggerCertainty.likely,
            source: '11 §28.2',
          ),
          HiddenTrigger(
            term: 'daal',
            certainty: TriggerCertainty.likely,
            source: '11 §28.2',
          ),
          HiddenTrigger(
            term: 'koshari',
            certainty: TriggerCertainty.likely,
            source: '11 §28.2',
          ),
          HiddenTrigger(
            term: 'kushari',
            certainty: TriggerCertainty.likely,
            source: '11 §28.2',
          ),
          HiddenTrigger(
            term: 'harira',
            certainty: TriggerCertainty.likely,
            source: '11 §28.1',
          ),
        ],
        guards: legumeGuards,
        sources: <String>['11 §16.1', '11 §28.2', '12 §1.3', '12 §12.2'],
      ),
      RestrictionId.pea: RestrictionVocabulary(
        directEn: <String>[...peaDirectEn, ...peaExtraEn],
        directHe: <String>[...peaDirectHe],
        hiddenEn: <HiddenTrigger>[
          // Pea protein in plant-based meat substitutes (11 §16.2, Allergy
          // UK); `legumes` has every one of these through soy or its own
          // list, so they are written here, not shared.
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
            term: 'meat substitute',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'meat alternative',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'beyond meat',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'beyond burger',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'vegetable protein',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.3',
          ),
          HiddenTrigger(
            term: 'samosa',
            certainty: TriggerCertainty.suspected,
            source: '11 §28.3',
          ),
          HiddenTrigger(
            term: 'samosas',
            certainty: TriggerCertainty.suspected,
            source: '11 §28.3',
          ),
          // Greek "fava" is yellow split peas (11 §28.3).
          HiddenTrigger(
            term: 'santorini fava',
            certainty: TriggerCertainty.likely,
            source: '11 §28.3',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'המבורגר טבעוני',
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
            term: 'ביונד מיט',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'ביונד בורגר',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.2',
          ),
          HiddenTrigger(
            term: 'חלבון צמחי',
            certainty: TriggerCertainty.suspected,
            source: '11 §16.3',
          ),
          HiddenTrigger(
            term: 'סמוסה',
            certainty: TriggerCertainty.suspected,
            source: '12 §12.3',
          ),
        ],
        guards: legumeGuards,
        termGuards: <String, AllergenGuards>{
          'pea': _notGardenPea,
          'peas': _notGardenPea,
        },
        sources: <String>[
          '11 §16.1',
          '11 §16.2',
          '11 §28.3',
          '12 §1.3',
          '12 §12.3',
        ],
      ),
      RestrictionId.fenugreek: RestrictionVocabulary(
        directEn: <String>[...fenugreekDirectEn, ...fenugreekExtraEn],
        directHe: <String>[...fenugreekDirectHe, ...fenugreekExtraHe],
        hiddenEn: <HiddenTrigger>[
          HiddenTrigger(
            term: 'panch phoron',
            certainty: TriggerCertainty.likely,
            source: '11 §28.4',
          ),
          // Saltah is served with hilbeh on top (11 §28.4).
          HiddenTrigger(
            term: 'saltah',
            certainty: TriggerCertainty.likely,
            source: '11 §28.4',
          ),
          // Many blends hold fenugreek, not all (11 §28.4).
          HiddenTrigger(
            term: 'curry powder',
            certainty: TriggerCertainty.suspected,
            source: '11 §28.4',
          ),
          HiddenTrigger(
            term: 'hawaij',
            certainty: TriggerCertainty.suspected,
            source: '11 §28.4',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          // Hilbeh is served with Yemenite soup (12 §1.3).
          HiddenTrigger(
            term: 'מרק תימני',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.3',
          ),
          HiddenTrigger(
            term: 'חוויג',
            certainty: TriggerCertainty.suspected,
            source: '12 §12.4',
          ),
          HiddenTrigger(
            term: 'חוואייג',
            certainty: TriggerCertainty.suspected,
            source: '12 §12.4',
          ),
          HiddenTrigger(
            term: 'אבקת קארי',
            certainty: TriggerCertainty.suspected,
            source: '12 §12.4',
          ),
        ],
        guards: legumeGuards,
        sources: <String>['11 §16.1', '11 §28.4', '12 §1.3', '12 §12.4'],
      ),
      RestrictionId.fava: RestrictionVocabulary(
        directEn: <String>[...favaDirectEn, ...favaExtraEn],
        directHe: <String>[...favaDirectHe],
        hiddenEn: <HiddenTrigger>[
          // Israeli falafel is chickpea (fava was dropped because of
          // favism); some falafel is fava or a mix (11 §28.5, 12 §1.3).
          HiddenTrigger(
            term: 'falafel',
            certainty: TriggerCertainty.suspected,
            source: '11 §28.5',
          ),
          // Egyptian ta'ameya is falafel of fava beans (11 §28.5).
          HiddenTrigger(
            term: "ta'ameya",
            certainty: TriggerCertainty.likely,
            source: '11 §28.5',
          ),
          HiddenTrigger(
            term: 'tamiya',
            certainty: TriggerCertainty.likely,
            source: '11 §28.5',
          ),
          HiddenTrigger(
            term: 'bissara',
            certainty: TriggerCertainty.likely,
            source: '11 §28.5',
          ),
        ],
        hiddenHe: <HiddenTrigger>[
          HiddenTrigger(
            term: 'פלאפל',
            certainty: TriggerCertainty.suspected,
            source: '12 §1.3',
          ),
        ],
        guards: legumeGuards,
        // Greek "fava" is a purée of yellow split peas, not fava beans
        // (11 §28.3): lowered, never cleared.
        termGuards: <String, AllergenGuards>{
          'fava': AllergenGuards(beforeEn: <String>['santorini', 'greek']),
        },
        noPrefixHe: <String>['פול'],
        sources: <String>[
          '11 §16.1',
          '11 §16.5',
          '11 §28.5',
          '12 §1.3',
          '12 §12.5',
        ],
      ),
    };
