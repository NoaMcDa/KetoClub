// AppSettings' group profiles (Banto; ALG-12, #354): the single stored
// profile migrates to "Me", the new keys are written only for more than
// the default, and every read is tolerant.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The keys group profiles add to the stored record.
const List<String> _groupKeys = <String>[
  'profileName',
  'groupProfiles',
  'activeProfiles',
];

/// Dana, holding milk.
final NamedProfile _dana = NamedProfile(
  id: 'p1',
  name: 'Dana',
  profile: DietaryProfile.empty.withEntry(RestrictionId.milk),
);

/// [json] with every key the stored record always has.
Map<String, Object?> _record(Map<String, Object?> json) => <String, Object?>{
  'filter': 'all',
  ...json,
};

void main() {
  group('AppSettings group profiles — migration', () {
    test('a single stored profile reads as one primary profile, "Me"', () {
      // Arrange: a record written before group profiles existed.
      final json = _record(<String, Object?>{
        'dietaryProfile': <Object?>[
          <String, Object?>{'id': 'sesame', 'exceptions': <Object?>[]},
        ],
      });

      // Act
      final settings = AppSettings.tryFrom(json)!;

      // Assert
      expect(settings.profiles, hasLength(1));
      final me = settings.profiles.single;
      expect(me.id, NamedProfile.primaryId);
      expect(me.isPrimary, isTrue);
      expect(me.name, isEmpty);
      expect(me.profile.contains(RestrictionId.sesame), isTrue);
      expect(settings.activeProfiles, <NamedProfile>[me]);
    });

    test('a keto install reads as one empty primary profile', () {
      // Act
      final settings = AppSettings.tryFrom(const AppSettings().toJson())!;

      // Assert
      expect(settings.profiles.single.profile, DietaryProfile.empty);
      expect(settings.activeProfileIds, AppSettings.defaultActiveProfileIds);
    });
  });

  group('AppSettings group profiles — what is written', () {
    test('defaults, and a single non-empty profile, write no group key', () {
      // Arrange
      final keto = const AppSettings().toJson();
      final single = AppSettings(
        profile: DietaryProfile.empty.withEntry(RestrictionId.gluten),
      ).toJson();

      // Assert
      for (final key in _groupKeys) {
        expect(keto.containsKey(key), isFalse, reason: key);
        expect(single.containsKey(key), isFalse, reason: key);
      }
    });

    test('a single-profile record is the pre-ALG-12 record, byte for byte', () {
      // Arrange: what a single-profile install stored before ALG-12.
      final profile = DietaryProfile.empty.withEntry(RestrictionId.gluten);
      final before = <String, Object?>{
        ...const AppSettings().toJson(),
        'dietaryProfile': profile.toJson(),
      };

      // Act
      final now = AppSettings(profile: profile).toJson();

      // Assert
      expect(jsonEncode(now), jsonEncode(before));
    });

    test('each group key is written once it differs from its default', () {
      // Arrange
      final settings = AppSettings(
        primaryProfileName: 'Noa',
        otherProfiles: <NamedProfile>[_dana],
        activeProfileIds: const <String>['me', 'p1'],
      );

      // Act
      final json = settings.toJson();

      // Assert
      expect(json['profileName'], 'Noa');
      expect(json['groupProfiles'], <Object?>[_dana.toJson()]);
      expect(json['activeProfiles'], <String>['me', 'p1']);
    });

    test('round-trips through JSON text', () {
      // Arrange
      final settings = AppSettings(
        profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        primaryProfileName: 'Noa',
        otherProfiles: <NamedProfile>[_dana],
        activeProfileIds: const <String>['p1'],
      );

      // Act
      final decoded =
          jsonDecode(jsonEncode(settings.toJson())) as Map<String, Object?>;
      final read = AppSettings.tryFrom(decoded);

      // Assert
      expect(read, settings);
      expect(read!.activeProfiles, <NamedProfile>[_dana]);
    });

    test('toString names counts, never a name or a restriction', () {
      // Arrange
      final settings = AppSettings(otherProfiles: <NamedProfile>[_dana]);

      // Act
      final text = settings.toString();

      // Assert
      expect(text, isNot(contains('Dana')));
      expect(text, isNot(contains('milk')));
      expect(_dana.toString(), isNot(contains('Dana')));
    });
  });

  group('AppSettings group profiles — tolerant reads', () {
    test('a non-string name reads as empty', () {
      // Act
      final settings = AppSettings.tryFrom(
        _record(<String, Object?>{'profileName': 7}),
      )!;

      // Assert
      expect(settings.primaryProfileName, isEmpty);
    });

    test('unreadable, repeated and primary-id profiles are dropped', () {
      // Act
      final settings = AppSettings.tryFrom(
        _record(<String, Object?>{
          'groupProfiles': <Object?>[
            'not an object',
            <String, Object?>{'name': 'No id'},
            <String, Object?>{'id': 'me', 'name': 'Impostor'},
            _dana.toJson(),
            <String, Object?>{'id': 'p1', 'name': 'Again'},
            <String, Object?>{
              'id': 'p2',
              'name': 42,
              'restrictions': <Object?>[
                <String, Object?>{'id': 'unknown-id'},
              ],
            },
          ],
        }),
      )!;

      // Assert
      expect(settings.otherProfiles.map((named) => named.id).toList(), <String>[
        'p1',
        'p2',
      ]);
      expect(settings.otherProfiles.first, _dana);
      expect(settings.otherProfiles.last.name, isEmpty);
      expect(settings.otherProfiles.last.profile, DietaryProfile.empty);
    });

    test('more than the maximum is cut', () {
      // Act
      final settings = AppSettings.tryFrom(
        _record(<String, Object?>{
          'groupProfiles': <Object?>[
            for (var i = 0; i < 20; i++)
              <String, Object?>{'id': 'p$i', 'name': 'P$i'},
          ],
        }),
      )!;

      // Assert
      expect(settings.profiles, hasLength(NamedProfile.maxProfiles));
    });

    test('a non-list groupProfiles reads as none', () {
      // Act
      final settings = AppSettings.tryFrom(
        _record(<String, Object?>{'groupProfiles': 'x'}),
      )!;

      // Assert
      expect(settings.otherProfiles, isEmpty);
    });

    test('unknown or repeated active ids are dropped, none means "me"', () {
      // Act
      final some = AppSettings.tryFrom(
        _record(<String, Object?>{
          'groupProfiles': <Object?>[_dana.toJson()],
          'activeProfiles': <Object?>['p1', 'gone', 'p1', 3],
        }),
      )!;
      final none = AppSettings.tryFrom(
        _record(<String, Object?>{
          'activeProfiles': <Object?>['gone'],
        }),
      )!;
      final wrongType = AppSettings.tryFrom(
        _record(<String, Object?>{'activeProfiles': 'me'}),
      )!;

      // Assert
      expect(some.activeProfileIds, <String>['p1']);
      expect(none.activeProfileIds, AppSettings.defaultActiveProfileIds);
      expect(wrongType.activeProfileIds, AppSettings.defaultActiveProfileIds);
    });

    test('activeProfiles falls back to the primary for a stale id', () {
      // Arrange: held in memory with an id no profile has.
      const settings = AppSettings(activeProfileIds: <String>['gone']);

      // Act + Assert
      expect(settings.activeProfiles.single.id, NamedProfile.primaryId);
    });

    test('activeHasNonKetoEntry looks at every active profile', () {
      // Arrange
      final meOnly = AppSettings(otherProfiles: <NamedProfile>[_dana]);
      final both = meOnly.copyWith(activeProfileIds: <String>['me', 'p1']);

      // Act + Assert
      expect(meOnly.activeHasNonKetoEntry, isFalse);
      expect(both.activeHasNonKetoEntry, isTrue);
    });
  });

  group('PrefsSettingsStore with group profiles', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('a written group reads back', () async {
      // Arrange
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);
      final settings = AppSettings(
        otherProfiles: <NamedProfile>[_dana],
        activeProfileIds: const <String>['me', 'p1'],
      );

      // Act
      await store.write(settings);
      final read = await store.read();

      // Assert
      expect(read, settings);
    });
  });
}
