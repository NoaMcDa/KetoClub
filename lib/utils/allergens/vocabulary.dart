/// The allergen vocabulary registry (Banto; ALG-01, issue #343): every
/// restriction's [RestrictionVocabulary], assembled from the group files
/// (six, since ALG-17 a seventh for the extended restrictions, and since
/// issue #342 an eighth for kosher and halal) so that each group's pull
/// request touches only its own file.
///
/// Profile-independent (architecture.md D26, C1): the registry and the
/// matcher over it know nothing of anyone's profile.
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocab_dairy_eggs.dart';
import 'package:ketoclub/utils/allergens/vocab_diets.dart';
import 'package:ketoclub/utils/allergens/vocab_extended.dart';
import 'package:ketoclub/utils/allergens/vocab_gluten_grains.dart';
import 'package:ketoclub/utils/allergens/vocab_nuts_seeds.dart';
import 'package:ketoclub/utils/allergens/vocab_plants_additives.dart';
import 'package:ketoclub/utils/allergens/vocab_religious.dart';
import 'package:ketoclub/utils/allergens/vocab_sea.dart';
import 'package:ketoclub/utils/allergens/vocabulary_types.dart';

export 'package:ketoclub/utils/allergens/vocabulary_types.dart';

/// Every restriction's vocabulary, by id. The group maps are disjoint
/// and together cover every [RestrictionId] (a test asserts both; a key
/// repeated across them would also fail to compile, since a constant map
/// may not repeat a key).
const Map<RestrictionId, RestrictionVocabulary> allergenVocabulary =
    <RestrictionId, RestrictionVocabulary>{
      ...nutsSeedsVocabulary,
      ...dairyEggsVocabulary,
      ...glutenGrainsVocabulary,
      ...seaVocabulary,
      ...plantsAdditivesVocabulary,
      ...dietsVocabulary,
      ...extendedVocabulary,
      ...religiousVocabulary,
    };

/// The group maps, by file name, for the registry test.
const Map<String, Map<RestrictionId, RestrictionVocabulary>>
allergenVocabularyGroups = <String, Map<RestrictionId, RestrictionVocabulary>>{
  'vocab_nuts_seeds.dart': nutsSeedsVocabulary,
  'vocab_dairy_eggs.dart': dairyEggsVocabulary,
  'vocab_gluten_grains.dart': glutenGrainsVocabulary,
  'vocab_sea.dart': seaVocabulary,
  'vocab_plants_additives.dart': plantsAdditivesVocabulary,
  'vocab_diets.dart': dietsVocabulary,
  'vocab_extended.dart': extendedVocabulary,
  'vocab_religious.dart': religiousVocabulary,
};
