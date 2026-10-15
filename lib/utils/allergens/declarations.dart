/// Platform and restaurant declarations as evidence (Banto, ALG-09, issue
/// #351; architecture.md D26).
///
/// A declaration is what the platform or the restaurant itself says about
/// a dish: a Wolt `dietary_preferences` tag, 10bis's `kosher` flag, or —
/// the likelier shape on Israeli menus (file 12 §4.4) — free text such as
/// "טבעוני", "ללא גלוטן", "gluten-free" or 🌱 in the dish's name, its
/// description or its category heading. [Declarations.of] reads them all
/// into [Declaration]s; the on-device `ProfileEvaluator` lowers the
/// matching concerns by one step and never below `suspected` for a strict
/// entry (file 09: a declaration never clears a strict entry, because the
/// restaurant can be wrong).
///
/// Pure and profile-independent (D26 C1): every declaration is reported,
/// whatever anyone's profile. Terms compile as the keto vocabulary does
/// ([latinTriggerPattern], [hebrewTriggerPattern] over normalised text);
/// a conditional or negating word next to a term ("ניתן לקבל טבעוני",
/// "vegan option", "not vegan") cancels it through
/// [ClassificationRules.isGuarded]'s two-word window, since guarding a
/// declaration only ever withholds a lowering, which is the safe
/// direction. A symbol (🌱, 🌾) is matched on the raw text, because
/// normalisation strips it. The twin is `backend/app/keto/declarations.py`,
/// pinned by the `declarations.json` golden.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The [Dish.declaredTags] entry a 10bis dish flagged `kosher: true`
/// carries.
const String kosherDeclaredTag = 'kosher';

/// The normalised declared tags that mean "kosher"
/// ([Declarations.declaresKosher]).
const List<String> kosherTags = <String>['kosher', 'כשר'];

/// Whether a declaration says a restriction's trigger is absent or
/// present.
///
/// Every rule in [declarationRules] declares an absence, as does a
/// restaurant allergen matrix's `free` cell (ALG-16). Nothing emits
/// [present]: a matrix's `contains` cell becomes a concern of its own
/// (`ConcernSource.matrix`), and the matcher already reads a "contains"
/// phrase as a stated trigger.
enum DeclarationPolarity {
  /// The dish is declared free of it ("gluten-free", "טבעוני").
  absent,

  /// The dish is declared to contain it.
  present,
}

/// Where a declaration was read.
enum DeclarationSource {
  /// A platform's own dietary tag ([Dish.declaredTags]).
  platformTag,

  /// The dish's own name or description, written by the restaurant.
  dishText,

  /// The dish's category heading, written by the restaurant.
  heading,

  /// The restaurant's allergen matrix (ALG-16,
  /// `utils/allergens/allergen_matrix.dart`): a `free` cell. Made on the
  /// device only; its [Declaration.matchedText] is the matrix row's
  /// printed name, so the user can see which row spoke for the dish.
  allergenMatrix,
}

/// One kind of self-declaration and what it says.
@immutable
final class DeclarationRule {
  /// Creates a rule named [id].
  const new({
    required this.id,
    required this.en,
    required this.he,
    required this.restrictions,
    this.symbols = const <String>[],
    this.polarity = DeclarationPolarity.absent,
  });

  /// A stable name for the rule ("vegan", "glutenFree").
  final String id;

  /// English terms, as written; each is normalised before it compiles.
  final List<String> en;

  /// Hebrew terms, as written, matched with the permissive prefix.
  final List<String> he;

  /// Symbols matched on the raw text ("🌱").
  final List<String> symbols;

  /// The restrictions the declaration speaks for, in taxonomy order.
  final List<RestrictionId> restrictions;

  /// Whether it declares them absent or present.
  final DeclarationPolarity polarity;
}

/// What a dish declares about one rule, read from one source.
@immutable
final class Declaration {
  /// Creates a declaration of [rule] read from [source].
  const new({
    required this.rule,
    required this.restrictionIds,
    required this.polarity,
    required this.source,
    required this.matchedText,
  });

  /// The [DeclarationRule.id] that matched.
  final String rule;

  /// The restrictions it speaks for, in taxonomy order.
  final List<RestrictionId> restrictionIds;

  /// Absent or present.
  final DeclarationPolarity polarity;

  /// Where it was read.
  final DeclarationSource source;

  /// The text that declared it: the tag as the platform wrote it, or the
  /// term or symbol as [declarationRules] writes it.
  final String matchedText;

  /// The golden form: every field by name.
  Map<String, Object?> toJson() => <String, Object?>{
    'rule': rule,
    'restrictionIds': <String>[for (final id in restrictionIds) id.name],
    'polarity': polarity.name,
    'source': source.name,
    'matchedText': matchedText,
  };

  @override
  bool operator ==(Object other) =>
      other is Declaration &&
      other.rule == rule &&
      listEquals(other.restrictionIds, restrictionIds) &&
      other.polarity == polarity &&
      other.source == source &&
      other.matchedText == matchedText;

  @override
  int get hashCode => Object.hash(
    rule,
    Object.hashAll(restrictionIds),
    polarity,
    source,
    matchedText,
  );

  @override
  String toString() =>
      'Declaration($rule ${polarity.name} from ${source.name}: '
      '"$matchedText")';
}

/// Every self-declaration the app reads, in the order it reports them.
///
/// Sources: file 12 §4.4 (Wolt's 🌱/🌾 venue tags, 10bis's "ללא גלוטן" and
/// "טבעוני" in headings and names) and file 10 §ALG-09 (vegan clears vegan
/// and vegetarian and marks milk and eggs absent; gluten-free clears
/// gluten). A vegan dish also declares no lactose and no seafood, a
/// vegetarian one no seafood. Gluten-free speaks for gluten only, never
/// wheat: a gluten-free product may still hold wheat starch. "Parve"
/// (פרווה) is left out on purpose: a parve label is a kosher category,
/// not a milk-allergy statement.
const List<DeclarationRule> declarationRules = <DeclarationRule>[
  DeclarationRule(
    id: 'vegan',
    en: <String>['vegan', 'plant based'],
    he: <String>['טבעוני', 'טבעונית', 'טבעוניים', 'טבעוניות'],
    symbols: <String>['🌱'],
    restrictions: <RestrictionId>[
      RestrictionId.milk,
      RestrictionId.lactose,
      RestrictionId.eggs,
      RestrictionId.fish,
      RestrictionId.crustaceans,
      RestrictionId.molluscs,
      RestrictionId.vegan,
      RestrictionId.vegetarian,
    ],
  ),
  DeclarationRule(
    id: 'vegetarian',
    en: <String>['vegetarian'],
    he: <String>['צמחוני', 'צמחונית', 'צמחוניים', 'צמחוניות'],
    restrictions: <RestrictionId>[
      RestrictionId.fish,
      RestrictionId.crustaceans,
      RestrictionId.molluscs,
      RestrictionId.vegetarian,
    ],
  ),
  DeclarationRule(
    id: 'glutenFree',
    en: <String>['gluten free', 'without gluten', 'gf'],
    he: <String>[
      'ללא גלוטן',
      'נטול גלוטן',
      'נטולת גלוטן',
      'נטולי גלוטן',
      'נטולות גלוטן',
      'בלי גלוטן',
    ],
    symbols: <String>['🌾'],
    restrictions: <RestrictionId>[RestrictionId.gluten],
  ),
  DeclarationRule(
    id: 'dairyFree',
    en: <String>['dairy free', 'milk free', 'without dairy'],
    he: <String>[
      'ללא חלב',
      'ללא מוצרי חלב',
      'נטול חלב',
      'נטולת חלב',
      'נטול מוצרי חלב',
      'בלי חלב',
    ],
    restrictions: <RestrictionId>[RestrictionId.milk, RestrictionId.lactose],
  ),
  DeclarationRule(
    id: 'lactoseFree',
    en: <String>['lactose free'],
    he: <String>['ללא לקטוז', 'נטול לקטוז', 'נטולת לקטוז'],
    restrictions: <RestrictionId>[RestrictionId.lactose],
  ),
  DeclarationRule(
    id: 'eggFree',
    en: <String>['egg free', 'eggless', 'without eggs'],
    he: <String>['ללא ביצים', 'ללא ביצה', 'נטול ביצים', 'בלי ביצים'],
    restrictions: <RestrictionId>[RestrictionId.eggs],
  ),
];

/// Words that, within two words of an English term, make it no
/// declaration: a negation ("not vegan", "non-vegan") or an offer rather
/// than a fact ("can be made gluten free", "vegan option available").
const GuardWords declarationGuardsEn = (
  before: <String>['not', 'non', 'no', 'can', 'made', 'optional', 'ask'],
  after: <String>[
    'option',
    'options',
    'optional',
    'available',
    'on request',
    'upon request',
    'version',
    'alternative',
    'substitute',
  ],
);

/// Words that, within two words of a Hebrew term, make it no declaration:
/// "לא טבעוני", "ניתן לקבל טבעוני", "יש גם ללא גלוטן", "טבעוני לפי בקשה",
/// "ללא גלוטן בתוספת תשלום".
const GuardWords declarationGuardsHe = (
  before: <String>['לא', 'ניתן', 'אפשר', 'אפשרות', 'באפשרות', 'יש', 'לבקש'],
  after: <String>[
    'לפי בקשה',
    'בהזמנה',
    'בתוספת',
    'באפשרות',
    'בתיאום',
    'לבקשה',
    'אופציה',
  ],
);

/// One compiled term of a rule.
typedef _Term = ({String term, RegExp pattern, bool hebrew});

/// One rule with its terms compiled.
typedef _CompiledRule = ({DeclarationRule rule, List<_Term> terms});

/// [declarationRules] compiled once.
final List<_CompiledRule> _compiled = <_CompiledRule>[
  for (final rule in declarationRules)
    (
      rule: rule,
      terms: <_Term>[
        for (final term in rule.en)
          (
            term: term,
            pattern: latinTriggerPattern(TextNormaliser.normalise(term)),
            hebrew: false,
          ),
        for (final term in rule.he)
          (
            term: term,
            pattern: hebrewTriggerPattern(TextNormaliser.normalise(term)),
            hebrew: true,
          ),
      ],
    ),
];

/// Reads platform and restaurant declarations (ALG-09).
abstract final class Declarations {
  /// Every declaration about [dish] under the category [heading]: its
  /// [Dish.declaredTags] first (one per tag and rule), then its name and
  /// description, then [heading]; one per rule and source, in
  /// [declarationRules] order. Pure; never throws.
  static List<Declaration> of(Dish dish, {String? heading}) =>
      List<Declaration>.unmodifiable(<Declaration>[
        ...ofTags(dish.declaredTags),
        ...inText(
          '${dish.name} ${dish.description}',
          DeclarationSource.dishText,
        ),
        if (heading != null) ...inText(heading, DeclarationSource.heading),
      ]);

  /// The declarations [tags] make, each tag read through the same table
  /// as menu text, with the tag itself as the matched text; one per rule,
  /// the first tag that makes it kept.
  static List<Declaration> ofTags(List<String> tags) {
    final found = <Declaration>[];
    for (final tag in tags) {
      for (final declaration in inText(tag, DeclarationSource.platformTag)) {
        if (found.any((kept) => kept.rule == declaration.rule)) continue;
        found.add(
          Declaration(
            rule: declaration.rule,
            restrictionIds: declaration.restrictionIds,
            polarity: declaration.polarity,
            source: DeclarationSource.platformTag,
            matchedText: tag,
          ),
        );
      }
    }
    return found;
  }

  /// The declarations [raw] makes, read as [source]: for each rule in
  /// order, its first unguarded English then Hebrew term, else its first
  /// symbol the raw text holds.
  static List<Declaration> inText(String raw, DeclarationSource source) {
    final haystack = TextNormaliser.normalise(raw);
    final found = <Declaration>[];
    for (final (:rule, :terms) in _compiled) {
      final matched = _firstTerm(haystack, terms) ?? _firstSymbol(raw, rule);
      if (matched == null) continue;
      found.add(
        Declaration(
          rule: rule.id,
          restrictionIds: rule.restrictions,
          polarity: rule.polarity,
          source: source,
          matchedText: matched,
        ),
      );
    }
    return found;
  }

  /// Whether the platform declared [dish] kosher: one of its declared
  /// tags normalises to one of [kosherTags]. The only kosher statement
  /// the app shows, and always attributed to the platform.
  static bool declaresKosher(Dish dish) => dish.declaredTags.any(
    (tag) => kosherTags.contains(TextNormaliser.normalise(tag)),
  );

  static String? _firstTerm(String haystack, List<_Term> terms) {
    for (final (:term, :pattern, :hebrew) in terms) {
      final guards = hebrew ? declarationGuardsHe : declarationGuardsEn;
      for (final match in pattern.allMatches(haystack)) {
        if (!ClassificationRules.isGuarded(
          haystack,
          match.start,
          match.end,
          guards,
        )) {
          return term;
        }
      }
    }
    return null;
  }

  static String? _firstSymbol(String raw, DeclarationRule rule) {
    for (final symbol in rule.symbols) {
      if (raw.contains(symbol)) return symbol;
    }
    return null;
  }
}
