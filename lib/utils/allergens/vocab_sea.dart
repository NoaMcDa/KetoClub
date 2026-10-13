/// Fish and seafood: the trigger vocabulary of fish, crustaceans and molluscs
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

/// Fish and seafood: one entry per restriction this group owns.
const Map<RestrictionId, RestrictionVocabulary> seaVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      // TODO(ALG-01): fill from docs 11 §8 and 12 §1.7, issue #343.
      RestrictionId.fish: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §9 and 12 §1.7, issue #343.
      RestrictionId.crustaceans: RestrictionVocabulary.empty,
      // TODO(ALG-01): fill from docs 11 §10 and 12 §1.7, issue #343.
      RestrictionId.molluscs: RestrictionVocabulary.empty,
    };
