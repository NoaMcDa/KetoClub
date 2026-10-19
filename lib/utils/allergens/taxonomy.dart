/// The restriction taxonomy: one [Restriction] per [RestrictionId]
/// (Banto; ALG-01, issue #343).
///
/// The kinds follow the owner's rule — no severity levels: an allergen or
/// an autoimmune condition is strict, everything else flexible
/// ([RestrictionKind.isStrict]). So [RestrictionId.milk] is the allergy
/// (strict) and [RestrictionId.lactose] the intolerance (flexible);
/// [RestrictionId.gluten] is celiac disease (autoimmune, strict), distinct
/// from [RestrictionId.wheat], the allergy.
///
/// The jurisdictions are the mandatory lists in
/// `allergen app documentation/02_regulated_allergens_by_jurisdiction.md`
/// ("The lists"): the Codex eight (peanuts, tree nuts, milk, eggs, soy,
/// wheat, fish, crustaceans) everywhere but Japan; the US adds sesame; the
/// EU, the UK and Israel add gluten cereals, celery, mustard, sesame,
/// lupin, molluscs and sulphites; Canada adds mustard, molluscs, sesame,
/// gluten and sulphites; Australia and New Zealand add sesame, lupin,
/// molluscs, sulphites and gluten (PEAL declares "gluten" beside wheat,
/// barley, oats and rye); Japan's mandatory list covers milk, eggs, wheat,
/// peanuts, crustaceans (shrimp, crab) and tree nuts (walnut, and cashew
/// since 1 April 2026) — its soy, sesame, fish and molluscs (squid,
/// abalone) are only recommended, and buckwheat has no id yet. Checked
/// 2026-10-19 (file 02, "The lists"; file 12 §8.1).
///
/// ALG-17 adds alpha-gal syndrome (an allergen: strict), FODMAP and
/// histamine (intolerances: flexible), small portions for GLP-1 eating (a
/// lifestyle: flexible; the three are [headsUpRestrictions]) and the
/// user's own free-text restriction, [RestrictionId.custom] (strict, as
/// file 10 §ALG-17 has it: an allergy by the user's word is an allergy).
/// None of them is on a labelling list.
///
/// The display names are shown beside the dish's own text and read to a
/// waiter, so like the waiter sentences in `constants.dart` they follow
/// the menu's language, not the UI locale (architecture.md §12), and live
/// here rather than in the ARB files. The Hebrew names are file 02's
/// "Hebrew terms" table.
library;

import 'package:ketoclub/models/restriction.dart';

/// Every jurisdiction: the Codex eight minus Japan's exceptions.
const Set<Jurisdiction> _everywhere = <Jurisdiction>{
  Jurisdiction.us,
  Jurisdiction.eu,
  Jurisdiction.uk,
  Jurisdiction.ca,
  Jurisdiction.anz,
  Jurisdiction.jp,
  Jurisdiction.il,
};

/// The Codex eight outside Japan's mandatory list (soy, fish).
const Set<Jurisdiction> _allButJapan = <Jurisdiction>{
  Jurisdiction.us,
  Jurisdiction.eu,
  Jurisdiction.uk,
  Jurisdiction.ca,
  Jurisdiction.anz,
  Jurisdiction.il,
};

/// The EU 14's own additions, which the UK and Israel share.
const Set<Jurisdiction> _euUkIl = <Jurisdiction>{
  Jurisdiction.eu,
  Jurisdiction.uk,
  Jurisdiction.il,
};

/// The restriction taxonomy, in [RestrictionId] order — one entry per id.
const List<Restriction> restrictionTaxonomy = <Restriction>[
  Restriction(
    id: RestrictionId.peanuts,
    kind: RestrictionKind.allergen,
    jurisdictions: _everywhere,
    nameEn: 'Peanuts',
    nameHe: 'בוטנים',
    source: '11 §1',
  ),
  Restriction(
    id: RestrictionId.treeNuts,
    kind: RestrictionKind.allergen,
    jurisdictions: _everywhere,
    nameEn: 'Tree nuts',
    nameHe: 'אגוזי עץ',
    source: '11 §2',
  ),
  Restriction(
    id: RestrictionId.milk,
    kind: RestrictionKind.allergen,
    jurisdictions: _everywhere,
    nameEn: 'Milk',
    nameHe: 'חלב',
    source: '11 §3',
  ),
  Restriction(
    id: RestrictionId.lactose,
    kind: RestrictionKind.intolerance,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Lactose',
    nameHe: 'לקטוז',
    source: '11 §4',
  ),
  Restriction(
    id: RestrictionId.eggs,
    kind: RestrictionKind.allergen,
    jurisdictions: _everywhere,
    nameEn: 'Eggs',
    nameHe: 'ביצים',
    source: '11 §5',
  ),
  Restriction(
    id: RestrictionId.soy,
    kind: RestrictionKind.allergen,
    jurisdictions: _allButJapan,
    nameEn: 'Soy',
    nameHe: 'סויה',
    source: '11 §6',
  ),
  Restriction(
    id: RestrictionId.wheat,
    kind: RestrictionKind.allergen,
    jurisdictions: _everywhere,
    nameEn: 'Wheat',
    nameHe: 'חיטה',
    source: '11 §7',
  ),
  Restriction(
    id: RestrictionId.gluten,
    kind: RestrictionKind.autoimmune,
    jurisdictions: <Jurisdiction>{
      ..._euUkIl,
      Jurisdiction.ca,
      Jurisdiction.anz,
    },
    nameEn: 'Gluten',
    nameHe: 'גלוטן',
    source: '11 §7',
  ),
  Restriction(
    id: RestrictionId.fish,
    kind: RestrictionKind.allergen,
    jurisdictions: _allButJapan,
    nameEn: 'Fish',
    nameHe: 'דגים',
    source: '11 §8',
  ),
  Restriction(
    id: RestrictionId.crustaceans,
    kind: RestrictionKind.allergen,
    jurisdictions: _everywhere,
    nameEn: 'Crustaceans',
    nameHe: 'סרטנאים',
    source: '11 §9',
  ),
  Restriction(
    id: RestrictionId.molluscs,
    kind: RestrictionKind.allergen,
    jurisdictions: <Jurisdiction>{
      ..._euUkIl,
      Jurisdiction.ca,
      Jurisdiction.anz,
    },
    nameEn: 'Molluscs',
    nameHe: 'רכיכות',
    source: '11 §10',
  ),
  Restriction(
    id: RestrictionId.sesame,
    kind: RestrictionKind.allergen,
    jurisdictions: _allButJapan,
    nameEn: 'Sesame',
    nameHe: 'שומשום',
    source: '11 §11',
  ),
  Restriction(
    id: RestrictionId.celery,
    kind: RestrictionKind.allergen,
    jurisdictions: _euUkIl,
    nameEn: 'Celery',
    nameHe: 'סלרי',
    source: '11 §12',
  ),
  Restriction(
    id: RestrictionId.mustard,
    kind: RestrictionKind.allergen,
    jurisdictions: <Jurisdiction>{..._euUkIl, Jurisdiction.ca},
    nameEn: 'Mustard',
    nameHe: 'חרדל',
    source: '11 §13',
  ),
  Restriction(
    id: RestrictionId.lupin,
    kind: RestrictionKind.allergen,
    jurisdictions: <Jurisdiction>{..._euUkIl, Jurisdiction.anz},
    nameEn: 'Lupin',
    nameHe: 'לופין',
    source: '11 §14',
  ),
  Restriction(
    id: RestrictionId.sulphites,
    kind: RestrictionKind.allergen,
    jurisdictions: <Jurisdiction>{
      ..._euUkIl,
      Jurisdiction.ca,
      Jurisdiction.anz,
    },
    nameEn: 'Sulphites',
    nameHe: 'סולפיטים',
    source: '11 §15',
  ),
  Restriction(
    id: RestrictionId.legumes,
    kind: RestrictionKind.allergen,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Legumes',
    nameHe: 'קטניות',
    source: '11 §16',
  ),
  Restriction(
    id: RestrictionId.alphaGal,
    kind: RestrictionKind.allergen,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Alpha-gal (mammal meat)',
    nameHe: 'אלפא-גל (בשר יונקים)',
    source: '11 §17',
  ),
  Restriction(
    id: RestrictionId.fodmap,
    kind: RestrictionKind.intolerance,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'FODMAP',
    nameHe: 'פודמאפ',
    source: '11 §21',
  ),
  Restriction(
    id: RestrictionId.histamine,
    kind: RestrictionKind.intolerance,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Histamine',
    nameHe: 'היסטמין',
    source: '11 §22',
  ),
  Restriction(
    id: RestrictionId.vegan,
    kind: RestrictionKind.lifestyle,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Vegan',
    nameHe: 'טבעוני',
    source: '12 §2.2',
  ),
  Restriction(
    id: RestrictionId.vegetarian,
    kind: RestrictionKind.lifestyle,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Vegetarian',
    nameHe: 'צמחוני',
    source: '12 §2.2',
  ),
  Restriction(
    id: RestrictionId.glp1,
    kind: RestrictionKind.lifestyle,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Small portions (GLP-1)',
    nameHe: 'מנות קטנות (GLP-1)',
    source: '11 §23',
  ),
  Restriction(
    id: RestrictionId.keto,
    kind: RestrictionKind.keto,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Keto',
    nameHe: 'קטו',
    source: '10 §ALG-01',
  ),
  Restriction(
    id: RestrictionId.custom,
    kind: RestrictionKind.allergen,
    jurisdictions: <Jurisdiction>{},
    nameEn: 'Your own restriction',
    nameHe: 'הגבלה משלך',
    source: '10 §ALG-17',
  ),
];

/// The restrictions whose concerns are a **heads-up**, never a verdict
/// (ALG-17): FODMAP and histamine are dose and preparation sensitivities
/// (onion in a sauce, an aged cheese grated on top), and GLP-1 eating is a
/// preference for small, light portions. A menu says nothing of the dose,
/// so `ProfileEvaluator` lowers every concern of these to `suspected`
/// ("may be high in …"), which a flexible entry lists and lets move
/// nothing: none of them ever makes a dish "avoid". The matcher still
/// reports their triggers as written (C1: extraction does not know who is
/// asking).
const Set<RestrictionId> headsUpRestrictions = <RestrictionId>{
  RestrictionId.fodmap,
  RestrictionId.histamine,
  RestrictionId.glp1,
};

/// The taxonomy entry for [id]. Total: [restrictionTaxonomy] holds one
/// entry per id, in [RestrictionId] order (a test pins both).
Restriction restrictionFor(RestrictionId id) => restrictionTaxonomy[id.index];

/// What a jurisdiction's allergen list binds (ALG-13, trip mode): food sold
/// packaged, or also the food a restaurant serves. [Restriction.jurisdictions]
/// says which lists name a restriction; this says whether naming it there
/// obliges a restaurant to tell a diner anything. Checked against web
/// sources on 2026-10-19 (file 12 §8.1 has each source and its URL).
enum ListScope {
  /// The list binds non-prepacked food too: a restaurant must be able to
  /// tell a diner which of the listed allergens a dish holds. The EU's
  /// Regulation 1169/2011, Article 44 (the means — in writing or orally —
  /// are left to each member state), and the UK's Food Information
  /// Regulations 2014, where telling orally is enough if a sign says so;
  /// the FSA's 2025 advice to give it in writing is best practice, not law
  /// (file 02, "The lists"; file 11 §19.2; file 12 §8.1).
  restaurants,

  /// The list binds packaged food only, and a restaurant owes a diner
  /// nothing today: Israel's rule, mandatory for prepacked food from
  /// 1 January 2028, with non-prepacked food deferred (a Ministry guide
  /// is reported to name 1 January 2032; unconfirmed), and Japan's Food
  /// Labeling Standards, which leave restaurants and food sold over the
  /// counter outside the allergen rules (file 12 §4.2, §8.1; file 11
  /// §19.3).
  packagedFood,

  /// The list binds packaged food (FALCPA and the FASTER Act), and only
  /// some chains must list allergens per dish: California's SB 68 (the
  /// ADDE Act, signed 13 October 2025), which from 1 July 2026 requires
  /// a chain of 20 or more locations to give written notice, on the menu
  /// or digitally, of which of the nine major allergens each item holds
  /// as an ingredient — and nothing about cross-contact (file 06; file 12
  /// §5, §8.1).
  packagedFoodAndLargeChains,
}

/// Each jurisdiction's [ListScope]. Canada and Australia / New Zealand are
/// not trip destinations yet and their restaurant rules were not
/// researched, so they read as [ListScope.packagedFood]: the hint that
/// follows is "ask every time", the side that never overstates a duty.
const Map<Jurisdiction, ListScope> jurisdictionListScope =
    <Jurisdiction, ListScope>{
      Jurisdiction.us: ListScope.packagedFoodAndLargeChains,
      Jurisdiction.eu: ListScope.restaurants,
      Jurisdiction.uk: ListScope.restaurants,
      Jurisdiction.ca: ListScope.packagedFood,
      Jurisdiction.anz: ListScope.packagedFood,
      Jurisdiction.jp: ListScope.packagedFood,
      Jurisdiction.il: ListScope.packagedFood,
    };
