/// Sensitivities: the trigger vocabulary of nightshades, MSG, caffeine,
/// salicylates and oral allergy syndrome (Banto; issue #342; file 03, "The
/// map"; file 02, "Less common allergens worth supporting").
///
/// All five are heads-up restrictions (`headsUpRestrictions` in
/// `taxonomy.dart`): a menu never states a dose, so `ProfileEvaluator`
/// reads every concern of theirs as "may be high in …", and none ever
/// moves a dish.
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

/// Sensitivities: one entry per restriction this group owns, each empty
/// until its follow-up fills it.
const Map<RestrictionId, RestrictionVocabulary> sensitivitiesVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.nightshades: RestrictionVocabulary.empty,
      RestrictionId.msg: RestrictionVocabulary.empty,
      RestrictionId.caffeine: RestrictionVocabulary.empty,
      RestrictionId.salicylates: RestrictionVocabulary.empty,
      RestrictionId.oralAllergy: RestrictionVocabulary.empty,
    };
