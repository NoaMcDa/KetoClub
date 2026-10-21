// ProfileWording.of (Banto, ALG-05, issue #347): keto-only unless the
// build is Banto and the profile holds a restriction besides keto; strict
// when one of them is an allergen or celiac disease.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/dietary_profile_strictness.dart';
import 'package:ketoclub/utils/profile_wording.dart';

void main() {
  final cases =
      <
        ({String name, DietaryProfile profile, bool banto, ProfileWording want})
      >[
        (
          name: 'empty, Banto',
          profile: DietaryProfile.empty,
          banto: true,
          want: ProfileWording.ketoOnly,
        ),
        (
          name: 'keto only, Banto',
          profile: DietaryProfile.empty.withEntry(RestrictionId.keto),
          banto: true,
          want: ProfileWording.ketoOnly,
        ),
        (
          name: 'peanuts, not Banto',
          profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
          banto: false,
          want: ProfileWording.ketoOnly,
        ),
        (
          name: 'peanuts, Banto',
          profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
          banto: true,
          want: ProfileWording.strict,
        ),
        (
          name: 'celiac, Banto',
          profile: DietaryProfile.empty.withEntry(RestrictionId.gluten),
          banto: true,
          want: ProfileWording.strict,
        ),
        (
          name: 'vegan and lactose, Banto',
          profile: DietaryProfile.empty
              .withEntry(RestrictionId.vegan)
              .withEntry(RestrictionId.lactose),
          banto: true,
          want: ProfileWording.flexible,
        ),
        (
          name: 'keto and vegan, Banto',
          profile: DietaryProfile.empty
              .withEntry(RestrictionId.keto)
              .withEntry(RestrictionId.vegan),
          banto: true,
          want: ProfileWording.flexible,
        ),
        // Kosher and halal are flexible, but "fits" beside them would read
        // as a certification (#342).
        (
          name: 'kosher, Banto',
          profile: DietaryProfile.empty.withEntry(RestrictionId.kosher),
          banto: true,
          want: ProfileWording.strict,
        ),
        (
          name: 'vegan and halal, Banto',
          profile: DietaryProfile.empty
              .withEntry(RestrictionId.vegan)
              .withEntry(RestrictionId.halal),
          banto: true,
          want: ProfileWording.strict,
        ),
        // Jain (#342) is the third religious component, by its kind: a
        // "fits" beside it would read as the kitchen's word too.
        (
          name: 'jain, Banto',
          profile: DietaryProfile.empty.withEntry(RestrictionId.jain),
          banto: true,
          want: ProfileWording.strict,
        ),
        (
          name: 'pescatarian, Banto',
          profile: DietaryProfile.empty.withEntry(RestrictionId.pescatarian),
          banto: true,
          want: ProfileWording.flexible,
        ),
        (
          name: 'kosher, not Banto',
          profile: DietaryProfile.empty.withEntry(RestrictionId.kosher),
          banto: false,
          want: ProfileWording.ketoOnly,
        ),
      ];

  for (final c in cases) {
    test('${c.name} is ${c.want.name}', () {
      // Act
      final wording = ProfileWording.of(c.profile, bantoMode: c.banto);

      // Assert
      expect(wording, c.want);
      expect(wording.usesStates, c.want != ProfileWording.ketoOnly);
    });
  }

  group('DietaryProfileScope', () {
    test('an empty profile holds keto and nothing else', () {
      expect(DietaryProfile.empty.holdsKeto, isTrue);
      expect(DietaryProfile.empty.hasNonKetoEntry, isFalse);
    });

    test('a sesame profile does not hold keto', () {
      final profile = DietaryProfile.empty.withEntry(RestrictionId.sesame);
      expect(profile.holdsKeto, isFalse);
      expect(profile.hasNonKetoEntry, isTrue);
    });

    test('keto and sesame holds both', () {
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.keto)
          .withEntry(RestrictionId.sesame);
      expect(profile.holdsKeto, isTrue);
      expect(profile.hasNonKetoEntry, isTrue);
    });
  });

  group('hasReligiousEntry', () {
    test('is kosher, halal or Jain, never another flexible entry', () {
      expect(
        DietaryProfile.empty.withEntry(RestrictionId.kosher).hasReligiousEntry,
        isTrue,
      );
      expect(
        DietaryProfile.empty.withEntry(RestrictionId.halal).hasReligiousEntry,
        isTrue,
      );
      expect(
        DietaryProfile.empty.withEntry(RestrictionId.jain).hasReligiousEntry,
        isTrue,
      );
      expect(
        DietaryProfile.empty.withEntry(RestrictionId.jain).hasStrictEntry,
        isFalse,
      );
      expect(
        DietaryProfile.empty.withEntry(RestrictionId.vegan).hasReligiousEntry,
        isFalse,
      );
      expect(
        DietaryProfile.empty.withEntry(RestrictionId.kosher).hasStrictEntry,
        isFalse,
      );
    });
  });
}
