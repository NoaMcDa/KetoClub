/// Whether a [DietaryProfile] holds a strict restriction (ALG-02a, issue
/// #344).
///
/// Lives in `utils/` rather than on the model because strictness is a
/// property of the taxonomy, not of the profile: an entry stores only its
/// id, and the kind that decides [RestrictionKind.isStrict] is looked up in
/// `restrictionTaxonomy`. `models/` may import nothing above itself
/// (architecture.md §5), so a getter on [DietaryProfile] would have to
/// store the kind on each entry (a second copy of the taxonomy that could
/// drift) or take a lookup callback. An extension one layer up keeps the
/// model a plain record and the taxonomy the one source of truth, and still
/// reads as `profile.hasStrictEntry` wherever this file is imported.
library;

import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// Strictness of a [DietaryProfile], derived from the taxonomy.
extension DietaryProfileStrictness on DietaryProfile {
  /// Whether any entry's restriction is strict: an allergen or an
  /// autoimmune condition ([RestrictionKind.isStrict]).
  bool get hasStrictEntry =>
      entries.any((entry) => restrictionFor(entry.restrictionId).isStrict);
}
