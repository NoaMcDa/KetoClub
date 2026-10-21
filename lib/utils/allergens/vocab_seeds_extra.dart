/// Seeds extra: the trigger vocabulary of corn, sunflower seeds and
/// flaxseed (Banto; issue #342; file 02, "Less common allergens worth
/// supporting").
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

/// Seeds extra: one entry per restriction this group owns, each empty
/// until its follow-up fills it.
const Map<RestrictionId, RestrictionVocabulary> seedsExtraVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.corn: RestrictionVocabulary.empty,
      RestrictionId.sunflower: RestrictionVocabulary.empty,
      RestrictionId.flax: RestrictionVocabulary.empty,
    };
