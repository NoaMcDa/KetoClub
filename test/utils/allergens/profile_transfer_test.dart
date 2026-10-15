// ProfileTransfer (Banto; ALG-12, #354): a profile shared as text and read
// back on another device.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/profile_transfer.dart';

void main() {
  group('ProfileTransfer', () {
    final profile = DietaryProfile.empty
        .withEntry(RestrictionId.milk, exceptions: <String>['butter'])
        .withEntry(RestrictionId.sesame);

    test('round-trips a name and restrictions', () {
      // Act
      final read = ProfileTransfer.decode(
        ProfileTransfer.encode(name: 'Dana', profile: profile),
      );

      // Assert
      expect(read, isNotNull);
      expect(read!.name, 'Dana');
      expect(read.profile, profile);
    });

    test('carries only the format, the name and the restrictions', () {
      // Act
      final json = jsonDecode(
        ProfileTransfer.encode(name: 'Dana', profile: profile),
      ) as Map<String, Object?>;

      // Assert
      expect(json.keys.toSet(), <String>{
        ProfileTransfer.formatKey,
        'name',
        'restrictions',
      });
    });

    test('reads the JSON out of a surrounding message', () {
      // Arrange
      final text =
          'Here is Dana: '
          '${ProfileTransfer.encode(name: 'Dana', profile: profile)} — bye';

      // Act
      final read = ProfileTransfer.decode(text);

      // Assert
      expect(read?.profile, profile);
    });

    test('refuses what is not a shared profile', () {
      // Act + Assert
      expect(ProfileTransfer.decode(''), isNull);
      expect(ProfileTransfer.decode('hello'), isNull);
      expect(ProfileTransfer.decode('{not json}'), isNull);
      expect(ProfileTransfer.decode('{"name": "Dana"}'), isNull);
      expect(ProfileTransfer.decode('{"bantoProfile": "1"}'), isNull);
      expect(
        ProfileTransfer.decode('{"bantoProfile": 1, "x": "${'a' * 9000}"}'),
        isNull,
      );
    });

    test('drops unknown ids and reads a missing name as empty', () {
      // Act
      final read = ProfileTransfer.decode(
        '{"bantoProfile": 1, "restrictions": '
        '[{"id": "from-the-future"}, {"id": "eggs"}]}',
      );

      // Assert
      expect(read!.name, isEmpty);
      expect(read.profile.entries.single.restrictionId, RestrictionId.eggs);
    });
  });
}
