/// The restriction taxonomy's model (Banto; the Allergens epic, ALG-01,
/// issue #343).
///
/// A [Restriction] is one thing a person can put in a dietary profile:
/// an allergen, an intolerance, celiac disease, a lifestyle diet or keto.
/// There are no severity levels. A restriction is either **strict** — its
/// [RestrictionKind] is [RestrictionKind.allergen] or
/// [RestrictionKind.autoimmune] — or **flexible** (every other kind).
/// Strictness is derived from the kind; it is never stored and never asked.
///
/// The entries themselves live in `lib/utils/allergens/taxonomy.dart`.
library;

import 'package:flutter/foundation.dart';

/// The stable id of one restriction. The names are the wire and storage
/// form, matched by name and never by ordinal, so reordering or adding a
/// value cannot re-map a stored profile; a rename needs a migration (a
/// test pins the list).
enum RestrictionId {
  /// Peanut allergy (a legume, not a tree nut).
  peanuts,

  /// Tree-nut allergy (almond, walnut, cashew, pistachio, hazelnut …).
  treeNuts,

  /// Cow's-milk allergy: the milk proteins, so lactose-free milk still
  /// counts.
  milk,

  /// Lactose intolerance: the milk sugar, distinct from [milk].
  lactose,

  /// Egg allergy.
  eggs,

  /// Soy allergy.
  soy,

  /// Wheat allergy, distinct from [gluten].
  wheat,

  /// Celiac disease: gluten from wheat, barley, rye and their relatives.
  gluten,

  /// Finfish allergy.
  fish,

  /// Crustacean shellfish allergy (shrimp, crab, lobster …).
  crustaceans,

  /// Mollusc allergy (squid, octopus, mussels, clams …).
  molluscs,

  /// Sesame allergy.
  sesame,

  /// Celery allergy.
  celery,

  /// Mustard allergy.
  mustard,

  /// Lupin allergy.
  lupin,

  /// Sulphite sensitivity (sulphur dioxide, E220–E228).
  sulphites,

  /// Legume allergy beyond peanut and soy (chickpea, lentil, pea, fava).
  legumes,

  /// Alpha-gal syndrome: an allergy to mammalian meat and its products
  /// (beef, lamb, pork, gelatin, lard; dairy for some). ALG-17.
  alphaGal,

  /// A low-FODMAP diet (IBS): a dose sensitivity, so its concerns are a
  /// heads-up and never rule a dish out. ALG-17.
  fodmap,

  /// Histamine intolerance: aged, smoked, pickled and fermented foods, a
  /// dose sensitivity read as a heads-up like [fodmap]. ALG-17.
  histamine,

  /// A vegan diet.
  vegan,

  /// A vegetarian diet.
  vegetarian,

  /// Small portions and lighter food, as people taking a GLP-1 medicine
  /// often eat: a preference signal read as a heads-up, never a ban.
  /// ALG-17.
  glp1,

  /// Kosher: the components a kosher diet leaves out (pork, shellfish,
  /// fish without fins and scales, blood, and meat served with dairy),
  /// flagged from the menu's words. Never a certification: whether a
  /// kitchen is kosher is the restaurant's to say (issue #342).
  kosher,

  /// Halal: the components a halal diet leaves out (pork, alcohol, blood
  /// and gelatin), flagged from the menu's words. Never a certification,
  /// as for [kosher].
  halal,

  /// Keto, the diet KetoClub was built for.
  keto,

  /// The user's own restriction: free-text terms ("kiwi", "כוסברה") kept in
  /// the profile entry's `terms` and matched literally on the device only
  /// (ALG-17; D26 C1). Strict: an allergy by the user's word is an allergy.
  custom;

  /// The id whose [name] equals [wire], or null when none does.
  ///
  /// Matches by string, never by ordinal.
  static RestrictionId? tryParse(String wire) {
    for (final id in RestrictionId.values) {
      if (id.name == wire) return id;
    }
    return null;
  }
}

/// What kind of restriction an entry is. Decides [isStrict].
enum RestrictionKind {
  /// An IgE food allergy: strict.
  allergen,

  /// An intolerance, such as lactose: flexible.
  intolerance,

  /// An autoimmune condition, such as celiac disease: strict.
  autoimmune,

  /// A lifestyle diet, such as vegan or vegetarian: flexible.
  lifestyle,

  /// A component of a religious rule — kosher and halal, read as the
  /// components a menu names, never as a certification: flexible.
  religiousComponent,

  /// Keto: flexible.
  keto;

  /// Whether a restriction of this kind is strict — an allergen or an
  /// autoimmune condition, where the app never says "fits" without "ask
  /// the restaurant". Every other kind is flexible.
  bool get isStrict => this == allergen || this == autoimmune;

  /// The kind whose [name] equals [wire], or null when none does.
  static RestrictionKind? tryParse(String wire) {
    for (final kind in RestrictionKind.values) {
      if (kind.name == wire) return kind;
    }
    return null;
  }
}

/// A jurisdiction whose allergen-labelling law names a restriction
/// (`allergen app documentation/02_regulated_allergens_by_jurisdiction.md`).
enum Jurisdiction {
  /// The United States (FALCPA and the FASTER Act).
  us,

  /// The European Union (Regulation 1169/2011).
  eu,

  /// The United Kingdom.
  uk,

  /// Canada.
  ca,

  /// Australia and New Zealand (PEAL).
  anz,

  /// Japan (the mandatory list only).
  jp,

  /// Israel (aligned to the EU list).
  il;

  /// The jurisdiction whose [name] equals [wire], or null when none does.
  static Jurisdiction? tryParse(String wire) {
    for (final jurisdiction in Jurisdiction.values) {
      if (jurisdiction.name == wire) return jurisdiction;
    }
    return null;
  }
}

/// One entry of the restriction taxonomy.
@immutable
final class Restriction {
  /// Creates the entry for [id].
  const new({
    required this.id,
    required this.kind,
    required this.jurisdictions,
    required this.nameEn,
    required this.nameHe,
    required this.source,
  });

  /// The stable id.
  final RestrictionId id;

  /// The kind, which decides [isStrict].
  final RestrictionKind kind;

  /// Where labelling law names this restriction; empty when nowhere does.
  final Set<Jurisdiction> jurisdictions;

  /// The English display name.
  final String nameEn;

  /// The Hebrew display name.
  final String nameHe;

  /// Where the entry comes from, as a short citation of the allergen
  /// documentation: `"11 §4"` is file 11, section 4.
  final String source;

  /// Whether this restriction is strict, derived from [kind].
  bool get isStrict => kind.isStrict;

  @override
  bool operator ==(Object other) =>
      other is Restriction &&
      other.id == id &&
      other.kind == kind &&
      setEquals(other.jurisdictions, jurisdictions) &&
      other.nameEn == nameEn &&
      other.nameHe == nameHe &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    Object.hashAllUnordered(jurisdictions),
    nameEn,
    nameHe,
    source,
  );

  @override
  String toString() => 'Restriction(${id.name}, ${kind.name})';
}
