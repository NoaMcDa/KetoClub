/// Nuts and seeds: the trigger vocabulary of peanuts, treeNuts and sesame
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

/// Nuts and seeds: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> nutsSeedsVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      // TODO(ALG-01): fill from docs 11 §1 and 12 §1.2, issue #343.
      RestrictionId.peanuts: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §2 and 12 §1.2, issue #343.
      RestrictionId.treeNuts: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §11 and 12 §1.1, issue #343.
      RestrictionId.sesame: RestrictionVocabulary.empty,
    };
