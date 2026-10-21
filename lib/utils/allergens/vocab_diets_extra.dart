/// Diets extra: the trigger vocabulary of the pescatarian, paleo,
/// Whole30, AIP and Jain diets (Banto; issue #342; file 03, "The map":
/// "easy to serve with rules").
///
/// Each is flexible (a lifestyle diet, or for Jain a religious component):
/// a hit means "the text names something this diet leaves out", never a
/// safety claim.
///
/// **Empty until its follow-up fills it**: this file is the contract step,
/// so every id is registered and no menu verdict changes. The picker
/// offers a restriction only once its vocabulary holds a term
/// (`restrictionOffered`), so none of these can be added yet.
///
/// Every term must cite its section, as `vocabulary_test.dart` checks;
/// after a change, regenerate the goldens and copy `allergens.json` to
/// `backend/app/keto/` (architecture.md D26).
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// Diets extra: one entry per restriction this group owns, each empty
/// until its follow-up fills it.
const Map<RestrictionId, RestrictionVocabulary> dietsExtraVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.pescatarian: RestrictionVocabulary.empty,
      RestrictionId.paleo: RestrictionVocabulary.empty,
      RestrictionId.whole30: RestrictionVocabulary.empty,
      RestrictionId.aip: RestrictionVocabulary.empty,
      RestrictionId.jain: RestrictionVocabulary.empty,
    };
