/// Diets: the trigger vocabulary of vegan, vegetarian and keto
/// (Banto; ALG-01, issue #343).
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

/// Diets: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> dietsVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      // TODO(ALG-01): fill from docs 11 §3.3 and 12 §2.2, issue #343.
      RestrictionId.vegan: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §5.3 and 12 §2.2, issue #343.
      RestrictionId.vegetarian: RestrictionVocabulary.empty,
      // Permanently empty: the keto vocabulary lives in
      // `lib/utils/constants.dart` and the rule engine, not
      // here. The entry exists so the registry covers every id.
      RestrictionId.keto: RestrictionVocabulary.empty,
    };
