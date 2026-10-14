import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/dietary_profile_strictness.dart';

/// [profile] through JSON text and back, as `SettingsStore` stores it.
DietaryProfile _roundTrip(DietaryProfile profile) =>
    DietaryProfile.tryFrom(jsonDecode(jsonEncode(profile.toJson())));

void main() {
  group('DietaryProfile', () {
    test('empty is empty, has no entries and no strict entry', () {
      // Assert
      expect(DietaryProfile.empty.isEmpty, isTrue);
      expect(DietaryProfile.empty.entries, isEmpty);
      expect(DietaryProfile.empty.hasStrictEntry, isFalse);
    });

    test('round-trips through JSON, keeping order and exceptions', () {
      // Arrange
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.sesame)
          .withEntry(RestrictionId.lactose, exceptions: <String>['butter'])
          .withEntry(RestrictionId.vegan);

      // Act
      final read = _roundTrip(profile);

      // Assert
      expect(read, profile);
      expect(read.entries.map((entry) => entry.restrictionId), <RestrictionId>[
        RestrictionId.sesame,
        RestrictionId.lactose,
        RestrictionId.vegan,
      ]);
      expect(read.entryFor(RestrictionId.lactose)!.exceptions, <String>[
        'butter',
      ]);
    });

    test('toJson writes ids by name', () {
      // Act
      final json = DietaryProfile.empty
          .withEntry(RestrictionId.treeNuts)
          .toJson();

      // Assert
      expect(json, <Map<String, Object?>>[
        <String, Object?>{'id': 'treeNuts', 'exceptions': <String>[]},
      ]);
    });

    group('tryFrom is tolerant', () {
      test('a value that is not a list reads as empty', () {
        for (final value in <Object?>[null, 'sesame', 3, <String, Object?>{}]) {
          expect(DietaryProfile.tryFrom(value), DietaryProfile.empty);
        }
      });

      test('an unknown id and a malformed item are dropped', () {
        // Act
        final profile = DietaryProfile.tryFrom(const <Object?>[
          <String, Object?>{'id': 'shellfish'},
          <String, Object?>{'id': 7},
          'sesame',
          null,
          <String, Object?>{'id': 'sesame'},
        ]);

        // Assert
        expect(profile.entries, <ProfileEntry>[
          const ProfileEntry(restrictionId: RestrictionId.sesame),
        ]);
      });

      test('a list of only unreadable items reads as empty', () {
        // Act
        final profile = DietaryProfile.tryFrom(const <Object?>[
          <String, Object?>{'id': 'unknown'},
        ]);

        // Assert
        expect(profile, DietaryProfile.empty);
      });

      test('a duplicate id keeps its first entry', () {
        // Act
        final profile = DietaryProfile.tryFrom(const <Object?>[
          <String, Object?>{
            'id': 'milk',
            'exceptions': <Object?>['ghee'],
          },
          <String, Object?>{
            'id': 'milk',
            'exceptions': <Object?>['cream'],
          },
        ]);

        // Assert
        expect(profile.entries, hasLength(1));
        expect(profile.entries.single.exceptions, <String>['ghee']);
      });

      test('exceptions that are not a list read as none; non-strings and '
          'blanks are dropped', () {
        // Act
        final profile = DietaryProfile.tryFrom(const <Object?>[
          <String, Object?>{'id': 'soy', 'exceptions': 'lecithin'},
          <String, Object?>{
            'id': 'eggs',
            'exceptions': <Object?>[1, '  ', ' mayo ', null, 'mayo'],
          },
        ]);

        // Assert
        expect(profile.entryFor(RestrictionId.soy)!.exceptions, isEmpty);
        expect(profile.entryFor(RestrictionId.eggs)!.exceptions, <String>[
          'mayo',
        ]);
      });

      test('exceptions are capped at 5, each at 60 characters', () {
        // Arrange
        final long = 'א' * 75;

        // Act
        final profile = DietaryProfile.tryFrom(<Object?>[
          <String, Object?>{
            'id': 'gluten',
            'exceptions': <Object?>[long, 'b', 'c', 'd', 'e', 'f', 'g'],
          },
        ]);

        // Assert
        final exceptions = profile.entryFor(RestrictionId.gluten)!.exceptions;
        expect(exceptions, hasLength(ProfileEntry.maxExceptions));
        expect(exceptions.first, 'א' * ProfileEntry.maxExceptionLength);
        expect(exceptions.skip(1), <String>['b', 'c', 'd', 'e']);
      });

      test('a cut never splits a character outside the BMP', () {
        // Arrange: 59 letters, then an emoji (two UTF-16 units) and more.
        final value = '${'a' * 59}🥜tail';

        // Act
        final exceptions = ProfileEntry.normaliseExceptions(<String>[value]);

        // Assert
        expect(exceptions.single, '${'a' * 59}🥜');
      });
    });

    group('withEntry', () {
      test('adds a new id last, with no exceptions', () {
        // Act
        final profile = DietaryProfile.empty
            .withEntry(RestrictionId.fish)
            .withEntry(RestrictionId.celery);

        // Assert
        expect(profile.entries.last.restrictionId, RestrictionId.celery);
        expect(profile.entries.last.exceptions, isEmpty);
        expect(profile.isEmpty, isFalse);
        expect(profile.contains(RestrictionId.fish), isTrue);
      });

      test('for a present id keeps its place and replaces the exceptions', () {
        // Arrange
        final profile = DietaryProfile.empty
            .withEntry(RestrictionId.milk, exceptions: <String>['ghee'])
            .withEntry(RestrictionId.eggs);

        // Act
        final updated = profile.withEntry(
          RestrictionId.milk,
          exceptions: <String>[' butter ', 'butter'],
        );
        final kept = updated.withEntry(RestrictionId.milk);

        // Assert
        expect(updated.entries.first.restrictionId, RestrictionId.milk);
        expect(updated.entries.first.exceptions, <String>['butter']);
        expect(updated.entries, hasLength(2));
        expect(kept, updated);
      });

      test('leaves the original profile unchanged', () {
        // Arrange
        const original = DietaryProfile.empty;

        // Act
        original.withEntry(RestrictionId.mustard);

        // Assert
        expect(original.isEmpty, isTrue);
      });
    });

    group('withoutEntry', () {
      test('removes the id and keeps the rest in order', () {
        // Arrange
        final profile = DietaryProfile.empty
            .withEntry(RestrictionId.peanuts)
            .withEntry(RestrictionId.lupin)
            .withEntry(RestrictionId.sulphites);

        // Act
        final removed = profile.withoutEntry(RestrictionId.lupin);

        // Assert
        expect(removed.entries.map((entry) => entry.restrictionId), [
          RestrictionId.peanuts,
          RestrictionId.sulphites,
        ]);
      });

      test('removing the last entry gives empty', () {
        // Act
        final profile = DietaryProfile.empty
            .withEntry(RestrictionId.vegan)
            .withoutEntry(RestrictionId.vegan);

        // Assert
        expect(profile, DietaryProfile.empty);
      });

      test('an absent id returns the same profile', () {
        // Arrange
        final profile = DietaryProfile.empty.withEntry(RestrictionId.soy);

        // Act / Assert
        expect(
          identical(profile.withoutEntry(RestrictionId.fish), profile),
          isTrue,
        );
      });
    });

    group('hasStrictEntry', () {
      test('is true for an allergen', () {
        expect(
          DietaryProfile.empty.withEntry(RestrictionId.sesame).hasStrictEntry,
          isTrue,
        );
      });

      test('is true for celiac (autoimmune)', () {
        expect(
          DietaryProfile.empty.withEntry(RestrictionId.gluten).hasStrictEntry,
          isTrue,
        );
      });

      test('is false for only flexible kinds', () {
        // Arrange
        final profile = DietaryProfile.empty
            .withEntry(RestrictionId.lactose)
            .withEntry(RestrictionId.vegan)
            .withEntry(RestrictionId.vegetarian)
            .withEntry(RestrictionId.keto);

        // Assert
        expect(profile.hasStrictEntry, isFalse);
      });

      test('is true when one of several entries is strict', () {
        // Arrange
        final profile = DietaryProfile.empty
            .withEntry(RestrictionId.vegan)
            .withEntry(RestrictionId.crustaceans);

        // Assert
        expect(profile.hasStrictEntry, isTrue);
      });
    });

    test('== and hashCode compare entries and exceptions by value', () {
      // Arrange
      final a = DietaryProfile.empty.withEntry(
        RestrictionId.milk,
        exceptions: <String>['ghee'],
      );
      final b = DietaryProfile.empty.withEntry(
        RestrictionId.milk,
        exceptions: <String>['ghee'],
      );
      final c = DietaryProfile.empty.withEntry(RestrictionId.milk);

      // Assert
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('toString names the entries and their exceptions', () {
      // Arrange
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.milk, exceptions: <String>['ghee'])
          .withEntry(RestrictionId.fish);

      // Assert
      expect(profile.toString(), 'DietaryProfile(milk (except ghee), fish)');
    });

    // (ids, hasNonKetoEntry)
    const nonKetoTable = <(List<RestrictionId>, bool)>[
      (<RestrictionId>[], false),
      (<RestrictionId>[RestrictionId.keto], false),
      (<RestrictionId>[RestrictionId.vegan], true),
      (<RestrictionId>[RestrictionId.keto, RestrictionId.sesame], true),
    ];
    for (final (ids, expected) in nonKetoTable) {
      test('hasNonKetoEntry is $expected for '
          '${ids.map((id) => id.name).toList()}', () {
        // Arrange
        var profile = DietaryProfile.empty;
        for (final id in ids) {
          profile = profile.withEntry(id);
        }

        // Assert
        expect(profile.hasNonKetoEntry, expected);
      });
    }
  });
}
