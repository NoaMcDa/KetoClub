import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A record with every field away from its default, consent withheld:
/// what a user who refused AI analysis and set everything else up keeps.
final AppSettings _everythingSet = AppSettings(
  languageTag: 'he',
  filter: MenuFilter.greenOnly,
  estimationConsentGiven: false,
  lastVenue: const VenueRef(source: MenuSource.wolt, platformId: 'v1'),
  themeMode: AppThemeMode.dark,
  netCarbLimitGrams: 12,
  seedOilFree: true,
  dairyFree: true,
  carnivoreOnly: true,
  lastFilter: MenuFilter.yellowOnly,
  disclosureSeen: true,
  profile: DietaryProfile.empty.withEntry(RestrictionId.fish),
  onboardingSeen: true,
  primaryProfileName: 'Dana',
  otherProfiles: <NamedProfile>[
    NamedProfile(
      id: 'p1',
      name: 'Noa',
      profile: DietaryProfile.empty.withEntry(RestrictionId.fish),
    ),
  ],
  activeProfileIds: const <String>[NamedProfile.primaryId, 'p1'],
  tripDestination: TripDestination.unitedStates,
  disclosureCopyVersion: 1,
  helperToolSeen: true,
  scanMonth: '2026-10',
  scanCount: 3,
  shareConfirmations: true,
  menuNudgeDismissed: true,
  discoveryNudgeDismissed: true,
);

/// [_everythingSet]'s stored JSON with [key] replaced by [value].
Map<String, Object?> _withCorrupt(String key, Object? value) =>
    <String, Object?>{..._everythingSet.toJson(), key: value};

/// A store over preferences holding [json] as the stored settings.
PrefsSettingsStore _storeHolding(Object json) {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.ketoclub_settings': json is String ? json : jsonEncode(json),
  });
  return PrefsSettingsStore(load: SharedPreferences.getInstance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('settings fields are read one by one (issue #281)', () {
    test('the record with every field set round-trips', () {
      expect(AppSettings.fromStored(_everythingSet.toJson()), _everythingSet);
    });

    test('a corrupt filter falls back to all and keeps consent withheld '
        'and every other field', () async {
      // Arrange: the reproduction, an unknown filter value.
      final store = _storeHolding(_withCorrupt('filter', 'greenOnlyish'));

      // Act
      final result = await store.read();

      // Assert
      expect(result.estimationConsentGiven, isFalse);
      expect(result, _everythingSet.copyWith(filter: MenuFilter.all));
    });

    test('an unknown lastVenue source (a downgrade from a newer build) '
        'reads as no venue and keeps consent withheld and every other '
        'field', () async {
      // Arrange: the reproduction, a source this build does not know.
      final store = _storeHolding(
        _withCorrupt('lastVenue', <String, Object?>{
          'source': 'opentable',
          'platformId': 'x',
        }),
      );

      // Act
      final result = await store.read();

      // Assert
      expect(result.estimationConsentGiven, isFalse);
      expect(result, _everythingSet.copyWith(lastVenue: null));
    });

    test('a corrupt filter and lastVenue together still keep consent '
        'withheld', () {
      final json = <String, Object?>{
        ..._withCorrupt('filter', 42),
        'lastVenue': 'not a map',
      };

      final result = AppSettings.fromStored(json);

      expect(result.estimationConsentGiven, isFalse);
      expect(
        result,
        _everythingSet.copyWith(filter: MenuFilter.all, lastVenue: null),
      );
    });

    test('consent fails closed: a stored value that is not a bool reads '
        'as withheld', () {
      for (final bad in <Object>[
        'true',
        1,
        0,
        <Object?>[],
        <String, Object?>{},
      ]) {
        final json = <String, Object?>{
          ...const AppSettings().toJson(),
          'estimationConsentGiven': bad,
        };

        expect(
          AppSettings.fromStored(json).estimationConsentGiven,
          isFalse,
          reason: 'stored consent $bad',
        );
      }
    });

    test('consent stays as stored when it is a bool, and a missing key is '
        'the D16 default of given', () {
      final json = const AppSettings().toJson();

      expect(
        AppSettings.fromStored(<String, Object?>{
          ...json,
          'estimationConsentGiven': false,
        }).estimationConsentGiven,
        isFalse,
      );
      expect(
        AppSettings.fromStored(<String, Object?>{
          ...json,
          'estimationConsentGiven': true,
        }).estimationConsentGiven,
        isTrue,
      );
      expect(
        AppSettings.fromStored(
          <String, Object?>{...json}..remove('estimationConsentGiven'),
        ).estimationConsentGiven,
        isTrue,
      );
    });

    // Each field, corrupted on its own, falls back to its own default and
    // leaves every other field — consent above all — as stored.
    final perField = <String, (Object?, AppSettings)>{
      'languageTag': (7, _everythingSet.copyWith(languageTag: null)),
      'themeMode': (
        'sepia',
        _everythingSet.copyWith(themeMode: AppThemeMode.system),
      ),
      'netCarbLimitGrams': (
        'twelve',
        _everythingSet.copyWith(netCarbLimitGrams: 6),
      ),
      'seedOilFree': ('yes', _everythingSet.copyWith(seedOilFree: false)),
      'dairyFree': (1, _everythingSet.copyWith(dairyFree: false)),
      'carnivoreOnly': (null, _everythingSet.copyWith(carnivoreOnly: false)),
      'lastFilter': ('nope', _everythingSet.copyWith(lastFilter: null)),
      'disclosureSeen': ('yes', _everythingSet.copyWith(disclosureSeen: false)),
      'dietaryProfile': (
        42,
        _everythingSet.copyWith(profile: DietaryProfile.empty),
      ),
      'restrictionOnboardingSeen': (
        'yes',
        _everythingSet.copyWith(onboardingSeen: false),
      ),
      'profileName': (7, _everythingSet.copyWith(primaryProfileName: '')),
      'groupProfiles': (
        'nobody',
        // Without the other person, only the primary profile stays active.
        _everythingSet.copyWith(
          otherProfiles: const <NamedProfile>[],
          activeProfileIds: AppSettings.defaultActiveProfileIds,
        ),
      ),
      'activeProfiles': (
        5,
        _everythingSet.copyWith(
          activeProfileIds: AppSettings.defaultActiveProfileIds,
        ),
      ),
      'tripDestination': (
        'atlantis',
        _everythingSet.copyWith(tripDestination: null),
      ),
      'disclosureCopyVersion': (
        'two',
        _everythingSet.copyWith(disclosureCopyVersion: 0),
      ),
      'helperToolSeen': (1, _everythingSet.copyWith(helperToolSeen: false)),
      'monthlyScans': (
        <Object?>[3],
        _everythingSet.copyWith(scanMonth: '', scanCount: 0),
      ),
      'shareConfirmations': (
        'true',
        _everythingSet.copyWith(shareConfirmations: false),
      ),
      'profileNudgeMenuDismissed': (
        1,
        _everythingSet.copyWith(menuNudgeDismissed: false),
      ),
      'profileNudgeDiscoveryDismissed': (
        'yes',
        _everythingSet.copyWith(discoveryNudgeDismissed: false),
      ),
    };
    for (final MapEntry(:key, value: (bad, expected)) in perField.entries) {
      test('a corrupt $key falls back to its own default only', () async {
        final store = _storeHolding(_withCorrupt(key, bad));

        final result = await store.read();

        expect(result, expected);
        expect(result.estimationConsentGiven, isFalse);
      });
    }

    test('the keto defaults are written byte for byte as before', () {
      expect(
        jsonEncode(const AppSettings().toJson()),
        '{"languageTag":null,"filter":"all","estimationConsentGiven":true,'
        '"lastVenue":null,"themeMode":"system","netCarbLimitGrams":6,'
        '"seedOilFree":false,"dairyFree":false,"carnivoreOnly":false,'
        '"lastFilter":null,"disclosureSeen":false}',
      );
    });
  });
}
