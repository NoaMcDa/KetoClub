/// What a Recent row remembers of the profile a menu was opened with
/// (Banto; the Allergens epic, issues #411 and #412; architecture.md D26).
///
/// Pure helpers, no I/O: the fingerprint of a profile's restriction ids, the
/// strict dishes a post-meal prompt asks about, and the names a "worked for
/// me" mark is stored under. All of it stays in the visit history on the
/// device (D23, D26 C1); none of it is a rating (D27).
library;

import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/visit_dish.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// The name a "worked for me" mark is stored under for the device owner's
/// own profile while they have not given it a name; shown in the UI's
/// language as the profile's default name.
const String workedForSelf = 'Me';

/// Eight lowercase hex digits of a 32-bit FNV-1a hash over the sorted
/// restriction ids of [profile], comma-joined: what tells a Recent row
/// that the profile it was counted for is not the profile now ("re-check").
/// Exceptions and the user's own words are not part of it, only which
/// restrictions the profile holds. An empty profile hashes the empty string.
String profileFingerprintOf(DietaryProfile profile) {
  final ids = <String>[
    for (final entry in profile.entries) entry.restrictionId.name,
  ]..sort();
  var hash = 0x811c9dc5;
  for (final unit in ids.join(',').codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// The dishes of [menu] that [evaluations] (keyed by dish id) found a
/// strict concern about, in menu order, as [VisitDish]es: the concerns of
/// strict restrictions only, those found in the dish itself (not the
/// kitchen's cross-contact or the restaurant's matrix, which the prompt
/// never asked about), once each. A dish with none is left out.
List<VisitDish> strictDishesOf(
  Menu menu,
  Map<String, EvaluatedDish> evaluations,
) {
  final dishes = <VisitDish>[];
  for (final category in menu.categories) {
    for (final dish in category.dishes) {
      final evaluated = evaluations[dish.id];
      if (evaluated == null) continue;
      final concerns = <VisitConcern>[];
      for (final concern in evaluated.concerns) {
        if (!restrictionFor(concern.restrictionId).isStrict) continue;
        if (concern.source == ConcernSource.kitchen ||
            concern.source == ConcernSource.matrix) {
          continue;
        }
        final kept = VisitConcern(
          restrictionId: concern.restrictionId,
          source: concern.source,
          matchedText: concern.matchedText,
        );
        if (!concerns.contains(kept)) concerns.add(kept);
      }
      if (concerns.isEmpty) continue;
      dishes.add(
        VisitDish(
          dishId: dish.id,
          name: dish.name,
          concerns: List<VisitConcern>.unmodifiable(concerns),
          hasChange: evaluated.modification != null,
        ),
      );
    }
  }
  return List<VisitDish>.unmodifiable(dishes);
}

/// The name [person] is marked under (`VisitEntry.workedFor`): their name,
/// else [workedForSelf] for the owner's own profile, else their id.
String workedForNameOf(NamedProfile person) {
  if (person.name.isNotEmpty) return person.name;
  return person.isPrimary ? workedForSelf : person.id;
}

/// The names in [marked] that belong to [people], in [marked]'s order:
/// the marked people the menu is read for now.
List<String> markedAmong(
  Iterable<String> marked,
  Iterable<NamedProfile> people,
) {
  final names = <String>{for (final person in people) workedForNameOf(person)};
  return <String>[
    for (final name in marked)
      if (names.contains(name)) name,
  ];
}
