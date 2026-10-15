// NamedProfile (Banto; ALG-12, #354): one person's profile, by name.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';

void main() {
  group('NamedProfile', () {
    test('normaliseName trims and caps by code point', () {
      // Arrange
      final long = '😀' * 50;

      // Act
      final capped = NamedProfile.normaliseName('  $long  ');

      // Assert
      expect(NamedProfile.normaliseName('  Dana  '), 'Dana');
      expect(capped.runes.length, NamedProfile.maxNameLength);
      expect(capped.runes.every((rune) => rune == '😀'.runes.single), isTrue);
    });

    test('round-trips through toJson and tryFrom', () {
      // Arrange
      final dana = NamedProfile(
        id: 'p1',
        name: 'Dana',
        profile: DietaryProfile.empty.withEntry(RestrictionId.milk),
      );

      // Act
      final read = NamedProfile.tryFrom(dana.toJson());

      // Assert
      expect(read, dana);
      expect(read.hashCode, dana.hashCode);
    });

    test('tryFrom refuses a non-object and a blank id', () {
      // Act + Assert
      expect(NamedProfile.tryFrom('x'), isNull);
      expect(NamedProfile.tryFrom(<String, Object?>{'id': '  '}), isNull);
      expect(NamedProfile.tryFrom(<String, Object?>{'id': 3}), isNull);
    });

    test('copyWith normalises a new name and keeps the id', () {
      // Arrange
      const dana = NamedProfile(id: 'p1', name: 'Dana');

      // Act
      final renamed = dana.copyWith(name: '  Dana (8) ');
      final edited = dana.copyWith(
        profile: DietaryProfile.empty.withEntry(RestrictionId.eggs),
      );

      // Assert
      expect(renamed.name, 'Dana (8)');
      expect(renamed.id, 'p1');
      expect(edited.name, 'Dana');
      expect(edited.profile.contains(RestrictionId.eggs), isTrue);
    });

    test('only the primary id is primary', () {
      // Act + Assert
      expect(
        const NamedProfile(id: NamedProfile.primaryId, name: '').isPrimary,
        isTrue,
      );
      expect(const NamedProfile(id: 'p1', name: 'Dana').isPrimary, isFalse);
    });
  });
}
