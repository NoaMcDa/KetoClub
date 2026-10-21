/// Foods extra: the trigger vocabulary of buckwheat and of the foods on
/// Japan's recommended allergen list that no other id covers — kiwi,
/// peach, apple, banana, orange, beef, pork, chicken, gelatin and yam
/// (Banto; issue #342).
///
/// Sources for the follow-up: file 02 ("The lists": Japan's mandatory
/// buckwheat and its 20 recommended items), file 11 §7.3 and §7.5
/// (buckwheat is not wheat: it stays a *guard* of wheat and gluten in
/// `vocab_gluten_grains.dart`, which lowers only their own triggers and
/// never a buckwheat hit), file 11 §17.1 (gelatin) and file 12 §8.2
/// (soba). Yam is Japan's yamaimo or nagaimo, not sweet potato (בטטה).
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

/// Foods extra: one entry per restriction this group owns, each empty
/// until its follow-up fills it.
const Map<RestrictionId, RestrictionVocabulary> foodsExtraVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.buckwheat: RestrictionVocabulary.empty,
      RestrictionId.kiwi: RestrictionVocabulary.empty,
      RestrictionId.peach: RestrictionVocabulary.empty,
      RestrictionId.apple: RestrictionVocabulary.empty,
      RestrictionId.banana: RestrictionVocabulary.empty,
      RestrictionId.orange: RestrictionVocabulary.empty,
      RestrictionId.beef: RestrictionVocabulary.empty,
      RestrictionId.pork: RestrictionVocabulary.empty,
      RestrictionId.chicken: RestrictionVocabulary.empty,
      RestrictionId.gelatin: RestrictionVocabulary.empty,
      RestrictionId.yam: RestrictionVocabulary.empty,
    };
