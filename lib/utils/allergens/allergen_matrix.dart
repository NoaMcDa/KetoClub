/// Matching a restaurant's allergen matrix to a menu, and what a matched
/// row says (Banto, ALG-16, related to #358; architecture.md D26).
///
/// [AllergenMatrixMatcher.match] pairs each [AllergenMatrixRow] with the
/// dishes it names, by the normaliser the response parser keys names by
/// (architecture.md §9.4: "of several elements whose names normalise alike,
/// the first is kept"; [TextNormaliser.normalise]): a row speaks for a dish
/// when one of the row's names (its printed name or an alias) normalises
/// to exactly what the dish's name normalises to. So "Purée" and "Puree",
/// "צ'יפס" and "ציפס", "סלט-חלומי" and "סלט חלומי", "בורקס" and "בורקס!" are
/// one name, and nothing looser is: §9.4 rule 3's shared-word test is how
/// the parser tells a reply from an invention, which is far too loose to
/// say whose allergens a dish has ("Chicken salad" is not "Chicken
/// schnitzel"). A row that names no dish, or only a dish another row also
/// names, is listed in [AllergenMatrixMatch.unmatched] and applied to
/// nothing: it is never guessed. A row naming a printed name two dishes
/// share (the same dish under two categories) speaks for both.
///
/// [AllergenMatrixMatcher.evidenceOf] turns a row into [MatrixEvidence]
/// for `ProfileEvaluator.evaluate`: a `contains` cell is a stated concern
/// and a `may_contain` cell a suspected one, both [ConcernSource.matrix]
/// at [EvidenceTier.declared]; the `free` cells are one absent
/// [Declaration], which the evaluator applies exactly as it applies
/// ALG-09's: one step lower, never below `suspected` and never removed for
/// a strict entry (file 09). A blank cell says nothing.
///
/// Matching lives on the device only, beside the evaluator that uses it
/// (the profile never leaves the device, D26 C1, and the device holds the
/// menu it renders). The backend stores and returns the restaurant's words
/// as written, and only refuses at intake two rows the device would read
/// as one dish, with the normaliser's pinned Python port. So there is no
/// Python twin and no golden. Pure; never throws.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/allergen_matrix.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The [Declaration.rule] of a matrix's `free` cells.
const String allergenMatrixRule = 'allergenMatrix';

/// What one matched matrix row says about its dish, for
/// `ProfileEvaluator.evaluate`.
@immutable
final class MatrixEvidence {
  /// Creates evidence of [concerns] and [absences].
  const new({
    this.concerns = const <Concern>[],
    this.absences = const <Declaration>[],
  });

  /// No matrix, or no row for the dish.
  static const MatrixEvidence none = MatrixEvidence();

  /// One concern per `contains` (stated) or `may_contain` (suspected)
  /// cell, at [EvidenceTier.declared], in [matrixColumns] order.
  final List<Concern> concerns;

  /// The `free` cells, as at most one absent declaration.
  final List<Declaration> absences;

  /// Whether the row said nothing (or there is no row).
  bool get isEmpty => concerns.isEmpty && absences.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is MatrixEvidence &&
      listEquals(other.concerns, concerns) &&
      listEquals(other.absences, absences);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(concerns), Object.hashAll(absences));
}

/// Why a matrix row was applied to no dish.
enum UnmatchedReason {
  /// None of its names normalises to a dish name on the menu.
  noDish,

  /// Every dish it names is named by another row too, so whose cells
  /// hold is a guess the app does not make.
  sharedDish,
}

/// A matrix row applied to no dish, and why.
typedef UnmatchedRow = ({AllergenMatrixRow row, UnmatchedReason reason});

/// One matrix matched against one menu.
@immutable
final class AllergenMatrixMatch {
  /// Creates the match of [matrix] with [rowsByDishId] applied.
  const new({
    required this.matrix,
    required this.rowsByDishId,
    required this.unmatched,
  });

  /// The matrix matched.
  final AllergenMatrix matrix;

  /// The row that speaks for each matched dish, by [Dish.id].
  final Map<String, AllergenMatrixRow> rowsByDishId;

  /// The rows applied to no dish, in the matrix's order.
  final List<UnmatchedRow> unmatched;

  /// The evidence for the dish [dishId]: its row's, or
  /// [MatrixEvidence.none] when no row speaks for it.
  MatrixEvidence evidenceFor(String dishId) {
    final row = rowsByDishId[dishId];
    return row == null
        ? MatrixEvidence.none
        : AllergenMatrixMatcher.evidenceOf(row);
  }
}

/// Matches allergen matrices to menus (ALG-16).
abstract final class AllergenMatrixMatcher {
  /// The key a name is matched by: [TextNormaliser.normalise], or null for
  /// a name with no letter or digit, which identifies nothing.
  static String? nameKey(String name) {
    final key = TextNormaliser.normalise(name);
    return key.isEmpty ? null : key;
  }

  /// [matrix]'s rows paired with [menu]'s dishes; see the library
  /// comment for the rule. Pure; never throws.
  static AllergenMatrixMatch match(AllergenMatrix matrix, Menu menu) {
    final dishesByKey = <String, List<String>>{};
    for (final dish in menu.allDishes) {
      final key = nameKey(dish.name);
      if (key == null) continue;
      (dishesByKey[key] ??= <String>[]).add(dish.id);
    }

    // Each dish id with every row (by index) that names it.
    final claims = <String, Set<int>>{};
    final named = <int, Set<String>>{};
    for (final (index, row) in matrix.rows.indexed) {
      final ids = <String>{
        for (final name in row.names)
          if (nameKey(name) case final key?) ...?dishesByKey[key],
      };
      named[index] = ids;
      for (final id in ids) {
        (claims[id] ??= <int>{}).add(index);
      }
    }

    final rowsByDishId = <String, AllergenMatrixRow>{};
    final unmatched = <UnmatchedRow>[];
    for (final (index, row) in matrix.rows.indexed) {
      final ids = named[index]!;
      final own = <String>[
        for (final id in ids)
          if (claims[id]!.length == 1) id,
      ];
      for (final id in own) {
        rowsByDishId[id] = row;
      }
      if (own.isEmpty) {
        unmatched.add((
          row: row,
          reason: ids.isEmpty
              ? UnmatchedReason.noDish
              : UnmatchedReason.sharedDish,
        ));
      }
    }
    return AllergenMatrixMatch(
      matrix: matrix,
      rowsByDishId: Map<String, AllergenMatrixRow>.unmodifiable(rowsByDishId),
      unmatched: List<UnmatchedRow>.unmodifiable(unmatched),
    );
  }

  /// What [row] says, as evidence: a concern per `contains` (stated) and
  /// `may_contain` (suspected) cell, [ConcernSource.matrix] at
  /// [EvidenceTier.declared] with no matched text, in [matrixColumns]
  /// order; and the `free` cells as one absent [Declaration] whose
  /// matched text is [AllergenMatrixRow.name]. Pure.
  static MatrixEvidence evidenceOf(AllergenMatrixRow row) {
    final concerns = <Concern>[];
    final free = <RestrictionId>[];
    for (final id in matrixColumns) {
      switch (row.cells[id]) {
        case MatrixCell.contains:
          concerns.add(_concern(id, Certainty.stated));
        case MatrixCell.mayContain:
          concerns.add(_concern(id, Certainty.suspected));
        case MatrixCell.free:
          free.add(id);
        case null:
          break;
      }
    }
    return MatrixEvidence(
      concerns: List<Concern>.unmodifiable(concerns),
      absences: List<Declaration>.unmodifiable(<Declaration>[
        if (free.isNotEmpty)
          Declaration(
            rule: allergenMatrixRule,
            restrictionIds: List<RestrictionId>.unmodifiable(free),
            polarity: DeclarationPolarity.absent,
            source: DeclarationSource.allergenMatrix,
            matchedText: row.name,
          ),
      ]),
    );
  }

  static Concern _concern(RestrictionId id, Certainty certainty) => Concern(
    restrictionId: id,
    source: ConcernSource.matrix,
    certainty: certainty,
    tier: EvidenceTier.declared,
  );
}
