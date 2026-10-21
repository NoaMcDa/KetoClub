/// Legume parts: the trigger vocabulary of each legume as its own toggle
/// under legumes — chickpea, lentil, pea and fenugreek — and of fava beans
/// for G6PD deficiency (Banto; issue #342; file 11 §16).
///
/// Sources for the follow-up: file 11 §16.1 (direct triggers: chickpea,
/// hummus, falafel, lentil and dal, pea and pea protein, fava and ful,
/// fenugreek), §16.2 (pea protein in plant-based meat), §16.5 ("model each
/// legume as its own toggle under a 'legumes' parent"; falafel is chickpea
/// and/or fava; favism is not an allergy) and file 12 (the Israeli menu
/// words).
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

/// Legume parts: one entry per restriction this group owns, each empty
/// until its follow-up fills it.
const Map<RestrictionId, RestrictionVocabulary> legumePartsVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      RestrictionId.chickpea: RestrictionVocabulary.empty,
      RestrictionId.lentil: RestrictionVocabulary.empty,
      RestrictionId.pea: RestrictionVocabulary.empty,
      RestrictionId.fenugreek: RestrictionVocabulary.empty,
      RestrictionId.fava: RestrictionVocabulary.empty,
    };
