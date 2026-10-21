import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store_contract.dart';

/// The method channel the default `SharedPreferencesStorePlatform`
/// (`MethodChannelSharedPreferencesStore`) talks to. Mocked directly, and
/// only by the very first test below, so `SharedPreferences.getInstance`
/// resolves through a real (mocked) channel rather than the in-memory
/// store `SharedPreferences.setMockInitialValues` installs for every
/// later test in this file.
const MethodChannel _prefsChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

/// A fresh [PrefsSettingsStore] whose loader is `SharedPreferences
/// .getInstance` over a freshly mocked, initially empty store.
PrefsSettingsStore _buildStore() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return PrefsSettingsStore(load: SharedPreferences.getInstance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Runs first, and deliberately outside every group below: it is the
  // only test that must see the real (mocked) shared_preferences channel
  // rather than the in-memory store `SharedPreferences
  // .setMockInitialValues` swaps in for every other test in this file.
  test(
    'write completes without throwing when the platform rejects the value',
    () async {
      // Arrange: the load succeeds (a plain "getAll") but the persist
      // call fails, driving PrefsSettingsStore.write's second catch —
      // the one guarding the actual disk write, not the load.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_prefsChannel, (call) async {
            switch (call.method) {
              case 'getAll':
                return <String, Object>{};
              case 'setString':
                throw PlatformException(code: 'boom', message: 'disk full');
              default:
                throw MissingPluginException('Unhandled: ${call.method}');
            }
          });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act & Assert
      await expectLater(store.write(const AppSettings()), completes);
    },
  );

  // Also runs before any `setMockInitialValues` call, for the same
  // reason as the test above — this one drives the write catch's other
  // branch, `on MissingPluginException`.
  test('write completes without throwing when no shared_preferences plugin '
      'is registered', () async {
    // Arrange
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_prefsChannel, (call) async {
          switch (call.method) {
            case 'getAll':
              return <String, Object>{};
            case 'setString':
              throw MissingPluginException('no plugin registered');
            default:
              throw MissingPluginException('Unhandled: ${call.method}');
          }
        });
    final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

    // Act & Assert
    await expectLater(store.write(const AppSettings()), completes);
  });

  runSettingsStoreContract('PrefsSettingsStore', _buildStore);

  group('PrefsSettingsStore', () {
    test('read returns defaults when the stored string is corrupt', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings': 'not valid json{',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(result, equals(const AppSettings()));
    });

    test(
      'read returns defaults when the stored JSON is shaped wrong',
      () async {
        // Arrange
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.ketoclub_settings': '"just a string, not a map"',
        });
        final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

        // Act
        final result = await store.read();

        // Assert
        expect(result, equals(const AppSettings()));
      },
    );

    test('an install that persisted greenAndYellow before issue #35 changed '
        'the default and the Settings control still loads it without a '
        'crash', () async {
      // Arrange: the exact JSON shape `PrefsSettingsStore` wrote before
      // `AppSettings`'s default filter changed from greenAndYellow to
      // all, and before the Settings screen's control dropped
      // greenAndYellow as a choice — `MenuFilter.tryParse` still knows
      // the name (models/analysis.dart), so this must decode cleanly
      // rather than falling back to today's defaults.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"languageTag":null,"filter":"greenAndYellow",'
            '"estimationConsentGiven":false,"lastVenue":null}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert: the persisted value survives, not today's default.
      expect(result.filter, equals(MenuFilter.greenAndYellow));
      expect(result.languageTag, isNull);
      expect(result.estimationConsentGiven, isFalse);
      expect(result.lastVenue, isNull);
    });

    test(
      'write then read round-trips languageTag and lastVenue as null',
      () async {
        // Arrange
        final store = _buildStore();
        await store.write(const AppSettings(languageTag: 'en'));

        // Act
        await store.write(const AppSettings());
        final result = await store.read();

        // Assert
        expect(result.languageTag, isNull);
        expect(result.lastVenue, isNull);
      },
    );

    test(
      'write then write replaces the settings rather than merging them',
      () async {
        // Arrange: the first write explicitly refuses consent so the
        // second write is seen to *replace* it, not merge with it. D16
        // (issue #167) flipped the default to true, so writing plain
        // defaults after this must read as true again.
        final store = _buildStore();
        await store.write(
          const AppSettings(
            languageTag: 'he',
            estimationConsentGiven: false,
            lastVenue: VenueRef(source: MenuSource.wolt, platformId: 'v1'),
          ),
        );

        // Act
        await store.write(const AppSettings(languageTag: 'en'));
        final result = await store.read();

        // Assert
        expect(result, equals(const AppSettings(languageTag: 'en')));
        expect(result.estimationConsentGiven, isTrue);
        expect(result.lastVenue, isNull);
      },
    );

    test('read returns defaults when the loader throws', () async {
      // Arrange
      final store = PrefsSettingsStore(
        load: () =>
            Future<SharedPreferences>.error(PlatformException(code: 'boom')),
      );

      // Act
      final result = await store.read();

      // Assert
      expect(result, equals(const AppSettings()));
    });

    test('read returns defaults when the loader throws no-plugin', () async {
      // Arrange
      final store = PrefsSettingsStore(
        load: () => Future<SharedPreferences>.error(
          MissingPluginException('no shared_preferences plugin'),
        ),
      );

      // Act
      final result = await store.read();

      // Assert
      expect(result, equals(const AppSettings()));
    });

    test('write completes without throwing when the loader throws', () async {
      // Arrange
      final store = PrefsSettingsStore(
        load: () => Future<SharedPreferences>.error(
          MissingPluginException('no shared_preferences plugin'),
        ),
      );

      // Act & Assert
      await expectLater(store.write(const AppSettings()), completes);
    });

    test(
      'the loader is invoked once across several read and write calls',
      () async {
        // Arrange
        SharedPreferences.setMockInitialValues(<String, Object>{});
        var loadCount = 0;
        final store = PrefsSettingsStore(
          load: () {
            loadCount++;
            return SharedPreferences.getInstance();
          },
        );

        // Act
        await store.read();
        await store.write(const AppSettings(languageTag: 'he'));
        await store.read();
        await store.write(const AppSettings(languageTag: 'en'));

        // Assert
        expect(loadCount, equals(1));
      },
    );

    test(
      'an install that persisted settings before issue #58 added themeMode '
      'decodes themeMode as system rather than failing the whole record',
      () async {
        // Arrange: the exact JSON shape PrefsSettingsStore wrote before
        // AppThemeMode existed — no "themeMode" key at all.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.ketoclub_settings':
              '{"languageTag":"he","filter":"greenOnly",'
              '"estimationConsentGiven":true,"lastVenue":null}',
        });
        final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

        // Act
        final result = await store.read();

        // Assert: every pre-existing field survives, and the new field
        // defaults rather than invalidating the record.
        expect(result.themeMode, equals(AppThemeMode.system));
        expect(result.languageTag, equals('he'));
        expect(result.filter, equals(MenuFilter.greenOnly));
        expect(result.estimationConsentGiven, isTrue);
      },
    );

    test('read decodes an unrecognised themeMode as system rather than '
        "falling back to today's defaults for the whole record", () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"languageTag":"he","filter":"all",'
            '"estimationConsentGiven":false,"lastVenue":null,'
            '"themeMode":"sepia"}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(result.themeMode, equals(AppThemeMode.system));
      expect(result.languageTag, equals('he'));
    });

    test(
      'an install that persisted settings before issue #57 added '
      'netCarbLimitGrams reads a 6 g limit and keeps every other field',
      () async {
        // Arrange: the JSON shape written before the limit existed.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.ketoclub_settings':
              '{"languageTag":"he","filter":"greenOnly",'
              '"estimationConsentGiven":true,"lastVenue":null,'
              '"themeMode":"dark"}',
        });
        final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

        // Act
        final result = await store.read();

        // Assert
        expect(result.netCarbLimitGrams, equals(6));
        expect(result.themeMode, equals(AppThemeMode.dark));
        expect(result.languageTag, equals('he'));
        expect(result.estimationConsentGiven, isTrue);
      },
    );

    test('read clamps a stored limit outside 2..25 g', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"languageTag":null,"filter":"all",'
            '"estimationConsentGiven":false,"lastVenue":null,'
            '"netCarbLimitGrams":40}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(result.netCarbLimitGrams, equals(25));
    });

    test(
      'an install that persisted settings before issue #56 added the '
      'dietary toggles reads all three as off and keeps every other field',
      () async {
        // Arrange: the JSON shape written before the toggles existed.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.ketoclub_settings':
              '{"languageTag":"he","filter":"greenOnly",'
              '"estimationConsentGiven":true,"lastVenue":null,'
              '"themeMode":"dark","netCarbLimitGrams":9}',
        });
        final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

        // Act
        final result = await store.read();

        // Assert
        expect(result.seedOilFree, isFalse);
        expect(result.dairyFree, isFalse);
        expect(result.carnivoreOnly, isFalse);
        expect(result.netCarbLimitGrams, equals(9));
        expect(result.languageTag, equals('he'));
        expect(result.estimationConsentGiven, isTrue);
      },
    );

    test('read treats a non-boolean toggle value as off', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"languageTag":null,"filter":"all",'
            '"estimationConsentGiven":false,"lastVenue":null,'
            '"seedOilFree":"yes","dairyFree":1,"carnivoreOnly":true}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(result.seedOilFree, isFalse);
      expect(result.dairyFree, isFalse);
      expect(result.carnivoreOnly, isTrue);
    });

    test('AppSettings.tryFrom decodes a stored consent value of false as '
        'false, so an install that already refused before D16 keeps its '
        'refusal (issue #167)', () {
      // Act: the legacy JSON shape carrying a refusal.
      final decoded = AppSettings.tryFrom(<String, Object?>{
        'languageTag': null,
        'filter': 'all',
        'estimationConsentGiven': false,
        'lastVenue': null,
      });

      // Assert
      expect(decoded, isNotNull);
      expect(decoded!.estimationConsentGiven, isFalse);
    });

    test('AppSettings.tryFrom decodes a missing estimationConsentGiven key '
        'as the D16 default of true (issue #167), so an install so old it '
        'predates the field lands on the new default rather than being '
        'invalidated for the whole record', () {
      // Act
      final decoded = AppSettings.tryFrom(<String, Object?>{
        'languageTag': null,
        'filter': 'all',
        'lastVenue': null,
      });

      // Assert
      expect(decoded, isNotNull);
      expect(decoded!.estimationConsentGiven, isTrue);
    });

    test('AppSettings.tryFrom round-trips disclosureSeen through toJson '
        'and back (issue #167)', () {
      // Arrange
      const settings = AppSettings(disclosureSeen: true);

      // Act
      final json = settings.toJson();
      final decoded = AppSettings.tryFrom(json);

      // Assert
      expect(json['disclosureSeen'], isTrue);
      expect(decoded, equals(settings));
    });

    test('AppSettings.tryFrom reads a missing disclosureSeen key as false '
        "(issue #167), so an install that predates D16 keeps 'not seen "
        "yet' and sees the banner once", () {
      // Act
      final decoded = AppSettings.tryFrom(<String, Object?>{
        'languageTag': null,
        'filter': 'all',
        'estimationConsentGiven': true,
        'lastVenue': null,
      });

      // Assert
      expect(decoded, isNotNull);
      expect(decoded!.disclosureSeen, isFalse);
    });

    test(
      'an install that persisted settings before issue #55 added '
      'lastFilter decodes lastFilter as null and keeps every other field',
      () async {
        // Arrange: the exact JSON shape PrefsSettingsStore wrote before
        // lastFilter existed — no "lastFilter" key at all.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.ketoclub_settings':
              '{"languageTag":"he","filter":"greenOnly",'
              '"estimationConsentGiven":true,"lastVenue":null,'
              '"themeMode":"dark","netCarbLimitGrams":9}',
        });
        final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

        // Act
        final result = await store.read();

        // Assert
        expect(result.lastFilter, isNull);
        expect(result.themeMode, equals(AppThemeMode.dark));
        expect(result.netCarbLimitGrams, equals(9));
        expect(result.languageTag, equals('he'));
        expect(result.filter, equals(MenuFilter.greenOnly));
      },
    );

    test('read decodes an unrecognised lastFilter as null rather than '
        "falling back to today's defaults for the whole record", () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"languageTag":"he","filter":"all",'
            '"estimationConsentGiven":false,"lastVenue":null,'
            '"lastFilter":"somethingUnknown"}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(result.lastFilter, isNull);
      expect(result.languageTag, equals('he'));
    });
  });

  group('onboardingSeen (ALG-02b, issue #344)', () {
    test('is written only when true, so a keto record is unchanged', () {
      final unset = const AppSettings().toJson();
      final set = const AppSettings(onboardingSeen: true).toJson();

      expect(unset.containsKey('restrictionOnboardingSeen'), isFalse);
      expect(set['restrictionOnboardingSeen'], isTrue);
    });

    test('round-trips through toJson and tryFrom', () {
      const settings = AppSettings(onboardingSeen: true);

      expect(AppSettings.tryFrom(settings.toJson()), equals(settings));
    });

    test('a missing or non-boolean value reads as not seen', () {
      final base = const AppSettings().toJson();

      expect(AppSettings.tryFrom(base)!.onboardingSeen, isFalse);
      expect(
        AppSettings.tryFrom(<String, Object?>{
          ...base,
          'restrictionOnboardingSeen': 'yes',
        })!.onboardingSeen,
        isFalse,
      );
    });

    test('survives a write and a read through the store', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      await store.write(const AppSettings(onboardingSeen: true));

      expect((await store.read()).onboardingSeen, isTrue);
    });
  });

  group('disclosureCopyVersion and helperToolSeen (ALG-11, issue #353)', () {
    test('are written only when set, so a keto record is unchanged', () {
      final unset = const AppSettings().toJson();
      final set = const AppSettings(
        disclosureCopyVersion: 1,
        helperToolSeen: true,
      ).toJson();

      expect(unset.containsKey('disclosureCopyVersion'), isFalse);
      expect(unset.containsKey('helperToolSeen'), isFalse);
      expect(set['disclosureCopyVersion'], 1);
      expect(set['helperToolSeen'], isTrue);
    });

    test('round-trip through toJson and tryFrom, and copyWith keeps them', () {
      const settings = AppSettings(
        disclosureCopyVersion: 2,
        helperToolSeen: true,
      );

      expect(AppSettings.tryFrom(settings.toJson()), equals(settings));
      expect(
        settings.copyWith(filter: MenuFilter.redOnly).helperToolSeen,
        isTrue,
      );
      expect(
        settings.copyWith(disclosureCopyVersion: 3).disclosureCopyVersion,
        3,
      );
      expect(settings, isNot(equals(const AppSettings())));
      expect(settings.hashCode, isNot(equals(const AppSettings().hashCode)));
      expect(settings.toString(), contains('disclosureCopyVersion: 2'));
    });

    test('a missing, negative or non-integer value reads as unset', () {
      final base = const AppSettings().toJson();

      expect(AppSettings.tryFrom(base)!.disclosureCopyVersion, 0);
      expect(AppSettings.tryFrom(base)!.helperToolSeen, isFalse);
      for (final raw in <Object?>[-1, '1', 1.5, null]) {
        expect(
          AppSettings.tryFrom(<String, Object?>{
            ...base,
            'disclosureCopyVersion': raw,
            'helperToolSeen': 'yes',
          }),
          const AppSettings(),
          reason: '$raw',
        );
      }
    });
  });

  group('shareConfirmations (ALG-14, issue #409)', () {
    test('is off by default and written only when on', () {
      final unset = const AppSettings().toJson();
      final set = const AppSettings(shareConfirmations: true).toJson();

      expect(const AppSettings().shareConfirmations, isFalse);
      expect(unset.containsKey('shareConfirmations'), isFalse);
      expect(set['shareConfirmations'], isTrue);
    });

    test('round-trips, and copyWith keeps and changes it', () {
      const settings = AppSettings(shareConfirmations: true);

      expect(AppSettings.tryFrom(settings.toJson()), equals(settings));
      expect(
        settings.copyWith(filter: MenuFilter.redOnly).shareConfirmations,
        isTrue,
      );
      expect(
        settings.copyWith(shareConfirmations: false),
        equals(const AppSettings()),
      );
      expect(settings, isNot(equals(const AppSettings())));
      expect(settings.hashCode, isNot(equals(const AppSettings().hashCode)));
      expect(settings.toString(), contains('shareConfirmations: true'));
    });

    test('an absent key, or anything but true, reads as off', () {
      final base = const AppSettings().toJson();

      expect(AppSettings.tryFrom(base)!.shareConfirmations, isFalse);
      for (final raw in <Object?>['true', 1, null, false]) {
        expect(
          AppSettings.tryFrom(<String, Object?>{
            ...base,
            'shareConfirmations': raw,
          })!.shareConfirmations,
          isFalse,
          reason: '$raw',
        );
      }
    });
  });

  group('PrefsSettingsStore dietary profile (ALG-02a, issue #344)', () {
    test('an install that stored settings before the profile existed reads '
        'an empty profile and keeps every other field', () async {
      // Arrange: no "dietaryProfile" key at all.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"languageTag":"he","filter":"greenOnly",'
            '"estimationConsentGiven":true,"lastVenue":null,'
            '"seedOilFree":true}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(result.profile, DietaryProfile.empty);
      expect(result.languageTag, 'he');
      expect(result.seedOilFree, isTrue);
    });

    test(
      'a malformed profile reads as empty without losing the record',
      () async {
        // Arrange
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.ketoclub_settings':
              '{"languageTag":"en","filter":"all",'
              '"estimationConsentGiven":false,"lastVenue":null,'
              '"dietaryProfile":"sesame"}',
        });
        final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

        // Act
        final result = await store.read();

        // Assert
        expect(result.profile, DietaryProfile.empty);
        expect(result.estimationConsentGiven, isFalse);
      },
    );

    test('a stored profile drops an unknown id and keeps the rest', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"languageTag":null,"filter":"all",'
            '"estimationConsentGiven":true,"lastVenue":null,'
            '"dietaryProfile":[{"id":"durian"},'
            '{"id":"sesame","exceptions":["tahini dressing"]}]}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(
        result.profile,
        DietaryProfile.empty.withEntry(
          RestrictionId.sesame,
          exceptions: <String>['tahini dressing'],
        ),
      );
    });

    test('the default settings write no dietaryProfile key', () async {
      // Arrange
      final store = _buildStore();

      // Act
      await store.write(const AppSettings());
      final prefs = await SharedPreferences.getInstance();

      // Assert
      expect(prefs.getString('ketoclub_settings'), isNot(contains('dietary')));
    });

    test('a non-empty profile is written under dietaryProfile', () async {
      // Arrange
      final store = _buildStore();
      final settings = AppSettings(
        profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
      );

      // Act
      await store.write(settings);
      final prefs = await SharedPreferences.getInstance();

      // Assert
      expect(
        prefs.getString('ketoclub_settings'),
        contains('"dietaryProfile":[{"id":"peanuts","exceptions":[]}]'),
      );
    });

    test('AppSettings.toString counts the entries and never names them', () {
      // Arrange
      final settings = AppSettings(
        profile: DietaryProfile.empty
            .withEntry(RestrictionId.sesame)
            .withEntry(RestrictionId.milk),
      );

      // Act
      final text = settings.toString();

      // Assert
      expect(text, contains('profile: 2 entries'));
      expect(text, isNot(contains('sesame')));
    });

    test('copyWith replaces the profile and keeps it when omitted', () {
      // Arrange
      final profile = DietaryProfile.empty.withEntry(RestrictionId.soy);
      final settings = const AppSettings().copyWith(profile: profile);

      // Act
      final kept = settings.copyWith(languageTag: 'he');

      // Assert
      expect(settings.profile, profile);
      expect(kept.profile, profile);
      expect(kept, isNot(const AppSettings(languageTag: 'he')));
    });
  });
}
