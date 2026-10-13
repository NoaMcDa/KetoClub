/// Plants and additives: the trigger vocabulary of soy, celery, mustard,
/// sulphites and legumes (Banto; ALG-01, issue #343).
///
/// A stub until its group pull request fills it. Every term comes from
/// `allergen app documentation/11_hidden_allergen_sources.md` or
/// `12_israeli_and_us_menu_lexicon.md` and its source cites the section
/// (`"11 §11"`, `"12 §1.1"`), which
/// `test/utils/allergens/vocabulary_test.dart` checks. After a change,
/// regenerate the goldens and copy `allergens.json` to
/// `backend/app/keto/` (architecture.md D26).
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// Plants and additives: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> plantsAdditivesVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      // TODO(ALG-01): fill from docs 11 §6 and 12 §1.11, issue #343.
      RestrictionId.soy: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §12 and 12 §1.9, issue #343.
      RestrictionId.celery: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §13 and 12 §1.8, issue #343.
      RestrictionId.mustard: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §15 and 12 §1.10, issue #343.
      RestrictionId.sulphites: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §16 and 12 §1.3, issue #343.
      RestrictionId.legumes: RestrictionVocabulary.empty,
    };
