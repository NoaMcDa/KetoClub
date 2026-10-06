/// The verdict counts a keto score is computed from, reduced from one
/// analysis over one menu in one place — the menu screen's header and
/// tiles, the Discovery card and the Recent tab all read these, so they
/// can never disagree about what counts (architecture.md D13, D21).
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/dish_kind.dart';
import 'package:ketoclub/utils/keto_score.dart';

/// How many of a menu's *food* dishes an analysis placed in each verdict
/// (D21): a drink, an extra or a notice line is still classified and
/// listed, but counts here for nothing. A dish the menu does not hold is
/// counted as food, since nothing says otherwise.
@immutable
final class VerdictCounts {
  /// Creates counts from the four numbers; [hiddenCarbYellow] is the part
  /// of [yellow] demoted from green by a hidden-carb flag (issue #213).
  const new({
    required this.green,
    required this.yellow,
    required this.hiddenCarbYellow,
    required this.red,
  }) : assert(hiddenCarbYellow <= yellow, 'hidden-carb yellows are yellows');

  /// The food-only counts of [analysis] over [menu].
  // A named constructor still needs its class name (see `VerdictTone.lerp`).
  // ignore: unnecessary_type_name_in_constructor
  factory VerdictCounts.of(Menu menu, MenuAnalysed analysis) {
    final kinds = dishKindsOf(menu);
    var green = 0;
    var yellow = 0;
    var hiddenCarbYellow = 0;
    var red = 0;
    for (final dish in analysis.dishes) {
      final kind = kinds[dish.dishId] ?? DishKind.food;
      if (!kind.countsTowardScore) continue;
      switch (dish.verdict) {
        case DishVerdict.orderAsIs:
          green++;
        case DishVerdict.modifiable:
          yellow++;
          if (dish.hiddenCarbs.isNotEmpty) hiddenCarbYellow++;
        case DishVerdict.nonKeto:
          red++;
      }
    }
    return VerdictCounts(
      green: green,
      yellow: yellow,
      hiddenCarbYellow: hiddenCarbYellow,
      red: red,
    );
  }

  /// No dish placed at all: every count zero, [score] null.
  static const VerdictCounts zero = VerdictCounts(
    green: 0,
    yellow: 0,
    hiddenCarbYellow: 0,
    red: 0,
  );

  /// Food dishes placed [DishVerdict.orderAsIs].
  final int green;

  /// Food dishes placed [DishVerdict.modifiable], hidden-carb ones included.
  final int yellow;

  /// The part of [yellow] demoted from green by a hidden-carb flag.
  final int hiddenCarbYellow;

  /// Food dishes placed [DishVerdict.nonKeto].
  final int red;

  /// The yellows that are not hidden-carb demotions.
  int get otherYellow => yellow - hiddenCarbYellow;

  /// Every placed food dish.
  int get total => green + yellow + red;

  /// [ketoScore] over these counts: null when no food dish was placed.
  double? get score => ketoScore(
    greenCount: green,
    hiddenCarbYellowCount: hiddenCarbYellow,
    otherYellowCount: otherYellow,
    redCount: red,
  );

  @override
  bool operator ==(Object other) =>
      other is VerdictCounts &&
      other.green == green &&
      other.yellow == yellow &&
      other.hiddenCarbYellow == hiddenCarbYellow &&
      other.red == red;

  @override
  int get hashCode => Object.hash(green, yellow, hiddenCarbYellow, red);

  @override
  String toString() =>
      'VerdictCounts(green: $green, yellow: $yellow, '
      'hiddenCarbYellow: $hiddenCarbYellow, red: $red)';
}
