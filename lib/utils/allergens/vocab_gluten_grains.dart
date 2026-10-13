/// Gluten and grains: the trigger vocabulary of wheat, gluten and lupin
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

/// Gluten and grains: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> glutenGrainsVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      // TODO(ALG-01): fill from docs 11 §7 and 12 §1.4, issue #343.
      RestrictionId.wheat: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §7 and 12 §1.4, issue #343.
      RestrictionId.gluten: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §14 and 12 §1.3, issue #343.
      RestrictionId.lupin: RestrictionVocabulary.empty,
    };
