import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/constants.dart';

import '../services/llm/llm_chat_client_contract.dart';
import '../services/storage/install_id_store_contract.dart';
import '../services/storage/menu_cache_contract.dart';
import '../services/storage/notes_store_contract.dart';
import '../services/storage/settings_store_contract.dart';
import 'fake_app_logger.dart';
import 'fake_clock.dart';
import 'fake_install_id_store.dart';
import 'fake_llm_chat_client.dart';
import 'fake_menu_cache.dart';
import 'fake_notes_store.dart';
import 'fake_settings_store.dart';

void main() {
  group('FakeClock', () {
    test('now returns the time it was created with', () {
      final clock = FakeClock(DateTime.utc(2026));

      expect(clock.now(), equals(DateTime.utc(2026)));
    });

    test('advance moves now forward by the given duration', () {
      final clock = FakeClock(DateTime.utc(2026))
        ..advance(const Duration(days: 1, hours: 2));

      expect(clock.now(), equals(DateTime.utc(2026, 1, 2, 2)));
    });

    test('now does not change on its own between calls', () {
      final clock = FakeClock(DateTime.utc(2026));

      final first = clock.now();
      final second = clock.now();

      expect(first, equals(second));
    });

    test('initial keeps the construction-time value across advances', () {
      final clock = FakeClock(DateTime.utc(2026))
        ..advance(const Duration(days: 1));

      expect(clock.initial, equals(DateTime.utc(2026)));
    });
  });

  group('FakeAppLogger', () {
    test('info records the message', () {
      final logger = FakeAppLogger()..info('fetched menu');

      expect(logger.infos, equals(<String>['fetched menu']));
    });

    test('warn records the message and the error', () {
      final logger = FakeAppLogger();
      final error = StateError('boom');

      logger.warn('cache miss', error: error);

      expect(logger.warnings, equals(<String>['cache miss']));
      expect(logger.warningErrors, equals(<Object?>[error]));
    });

    test('warn records null when no error is given', () {
      final logger = FakeAppLogger()..warn('cache miss');

      expect(logger.warningErrors, equals(<Object?>[null]));
    });

    test('info and warn are recorded in separate lists', () {
      final logger = FakeAppLogger()
        ..info('a')
        ..warn('b');

      expect(logger.infos, equals(<String>['a']));
      expect(logger.warnings, equals(<String>['b']));
    });
  });

  group('FakeLlmChatClient', () {
    test('complete returns queued results in enqueue order', () async {
      final client = FakeLlmChatClient()
        ..enqueue(const ChatCompleted(content: '{}', model: 'm1'))
        ..enqueue(const ChatFailed(reason: ChatFailureReason.timeout));

      final first = await client.complete(systemPrompt: 's', userPrompt: 'u');
      final second = await client.complete(systemPrompt: 's', userPrompt: 'u');

      expect(first, equals(const ChatCompleted(content: '{}', model: 'm1')));
      expect(
        second,
        equals(const ChatFailed(reason: ChatFailureReason.timeout)),
      );
    });

    test('complete returns fallback once the queue runs out', () async {
      final client = FakeLlmChatClient();

      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      expect(result, equals(client.fallback));
    });

    test('a steered fallback is returned when nothing is queued', () async {
      final client = FakeLlmChatClient()
        ..fallback = const ChatFailed(reason: ChatFailureReason.offline);

      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.offline)),
      );
    });

    test('complete records every request it receives', () async {
      final client = FakeLlmChatClient();

      await client.complete(
        systemPrompt: 'system',
        userPrompt: 'user',
        responseSchema: const <String, Object?>{'type': 'object'},
        schemaName: 'menu_analysis',
      );

      expect(client.requests, hasLength(1));
      final recorded = client.requests.single;
      expect(recorded.systemPrompt, equals('system'));
      expect(recorded.userPrompt, equals('user'));
      expect(
        recorded.responseSchema,
        equals(const <String, Object?>{'type': 'object'}),
      );
      expect(recorded.schemaName, equals('menu_analysis'));
    });

    test('complete records a request made with no schema', () async {
      final client = FakeLlmChatClient();

      await client.complete(systemPrompt: 'system', userPrompt: 'user');

      final recorded = client.requests.single;
      expect(recorded.responseSchema, isNull);
      expect(recorded.schemaName, isNull);
    });
  });

  group('CachedMenu', () {
    test('tryFrom(x.toJson()) round-trips a menu with no analysis', () {
      final entry = CachedMenu(menu: _menuFor(_woltRef));

      expect(CachedMenu.tryFrom(entry.toJson()), equals(entry));
    });

    test('tryFrom(x.toJson()) round-trips an LlmEngine analysis', () {
      final entry = CachedMenu(
        menu: _menuFor(_woltRef),
        analysis: MenuAnalysed(
          dishes: const <AnalysedDish>[],
          unclassified: const <String>['Mystery dish'],
          engine: const LlmEngine(model: 'test/model'),
          analysedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      expect(CachedMenu.tryFrom(entry.toJson()), equals(entry));
    });

    test('tryFrom(x.toJson()) round-trips a RulesEngine analysis', () {
      final entry = CachedMenu(
        menu: _menuFor(_woltRef),
        analysis: MenuAnalysed(
          dishes: const <AnalysedDish>[],
          unclassified: const <String>[],
          engine: const RulesEngine(reason: MenuAnalysisFailureReason.offline),
          analysedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      expect(CachedMenu.tryFrom(entry.toJson()), equals(entry));
    });

    test('tryFrom(x.toJson()) round-trips a failed analysis', () {
      final entry = CachedMenu(
        menu: _menuFor(_woltRef),
        analysis: const MenuAnalysisFailed(
          reason: MenuAnalysisFailureReason.timeout,
          detail: 'gateway timed out',
        ),
      );

      expect(CachedMenu.tryFrom(entry.toJson()), equals(entry));
    });

    test('tryFrom returns null when menu is missing', () {
      expect(CachedMenu.tryFrom(const <String, Object?>{}), isNull);
    });

    test('tryFrom returns null when menu is not a map', () {
      expect(
        CachedMenu.tryFrom(const <String, Object?>{'menu': 'nope'}),
        isNull,
      );
    });

    test('tryFrom returns null when menu is malformed', () {
      final json = <String, Object?>{
        'menu': <String, Object?>{'currency': 'ILS'},
      };

      expect(CachedMenu.tryFrom(json), isNull);
    });

    test('tryFrom returns null when analysis is not a map', () {
      final json = _menuFor(_woltRef).toJson();
      final entryJson = <String, Object?>{'menu': json, 'analysis': 'nope'};

      expect(CachedMenu.tryFrom(entryJson), isNull);
    });

    test('tryFrom returns null when analysis has no kind', () {
      final entryJson = <String, Object?>{
        'menu': _menuFor(_woltRef).toJson(),
        'analysis': <String, Object?>{},
      };

      expect(CachedMenu.tryFrom(entryJson), isNull);
    });

    test('tryFrom returns null when analysis kind is unknown', () {
      final entryJson = <String, Object?>{
        'menu': _menuFor(_woltRef).toJson(),
        'analysis': <String, Object?>{'kind': 'guessed'},
      };

      expect(CachedMenu.tryFrom(entryJson), isNull);
    });

    test('tryFrom returns null when an analysed analysis is malformed', () {
      final entryJson = <String, Object?>{
        'menu': _menuFor(_woltRef).toJson(),
        'analysis': <String, Object?>{'kind': 'analysed'},
      };

      expect(CachedMenu.tryFrom(entryJson), isNull);
    });

    test('tryFrom returns null when a failed analysis has no reason', () {
      final entryJson = <String, Object?>{
        'menu': _menuFor(_woltRef).toJson(),
        'analysis': <String, Object?>{'kind': 'failed'},
      };

      expect(CachedMenu.tryFrom(entryJson), isNull);
    });

    test(
      'tryFrom returns null when a failed analysis has an unknown reason',
      () {
        final entryJson = <String, Object?>{
          'menu': _menuFor(_woltRef).toJson(),
          'analysis': <String, Object?>{'kind': 'failed', 'reason': 'gremlins'},
        };

        expect(CachedMenu.tryFrom(entryJson), isNull);
      },
    );

    test(
      'tryFrom returns null when a failed analysis detail is not a string',
      () {
        final entryJson = <String, Object?>{
          'menu': _menuFor(_woltRef).toJson(),
          'analysis': <String, Object?>{
            'kind': 'failed',
            'reason': 'offline',
            'detail': 7,
          },
        };

        expect(CachedMenu.tryFrom(entryJson), isNull);
      },
    );

    test('== returns true for equal entries', () {
      final a = CachedMenu(menu: _menuFor(_woltRef));
      final b = CachedMenu(menu: _menuFor(_woltRef));

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for entries with different analyses', () {
      final a = CachedMenu(menu: _menuFor(_woltRef));
      final b = CachedMenu(
        menu: _menuFor(_woltRef),
        analysis: const MenuAnalysisFailed(
          reason: MenuAnalysisFailureReason.timeout,
        ),
      );

      expect(a, isNot(equals(b)));
    });

    test('toString mentions the venue cache key', () {
      final entry = CachedMenu(menu: _menuFor(_woltRef));

      expect(entry.toString(), contains('wolt/x'));
    });
  });

  group('AppThemeMode', () {
    test('tryParse finds every value by its own name', () {
      for (final mode in AppThemeMode.values) {
        expect(AppThemeMode.tryParse(mode.name), equals(mode));
      }
    });

    test('tryParse returns null for an unknown name', () {
      expect(AppThemeMode.tryParse('sepia'), isNull);
    });
  });

  group('AppSettings', () {
    test('defaults are all, no consent, no venue, no language, system '
        'appearance', () {
      const settings = AppSettings();

      expect(settings.languageTag, isNull);
      expect(settings.filter, equals(MenuFilter.all));
      expect(settings.estimationConsentGiven, isFalse);
      expect(settings.lastVenue, isNull);
      expect(settings.themeMode, equals(AppThemeMode.system));
    });

    test('tryFrom(x.toJson()) round-trips settings with every field set', () {
      const settings = AppSettings(
        languageTag: 'he',
        filter: MenuFilter.greenOnly,
        estimationConsentGiven: true,
        lastVenue: VenueRef(source: MenuSource.tenbis, platformId: '9'),
        themeMode: AppThemeMode.dark,
      );

      expect(AppSettings.tryFrom(settings.toJson()), equals(settings));
    });

    test('tryFrom(x.toJson()) round-trips every AppThemeMode value', () {
      for (final mode in AppThemeMode.values) {
        final settings = AppSettings(themeMode: mode);

        expect(AppSettings.tryFrom(settings.toJson()), equals(settings));
      }
    });

    test('tryFrom decodes a missing themeMode as system, issue #58 (added '
        'after installs already existed without it)', () {
      final json = <String, Object?>{
        'filter': 'all',
        'estimationConsentGiven': false,
      };

      final result = AppSettings.tryFrom(json);

      expect(result, isNotNull);
      expect(result!.themeMode, equals(AppThemeMode.system));
    });

    test('tryFrom decodes an unrecognised themeMode as system rather than '
        'invalidating the whole record', () {
      final json = <String, Object?>{
        'filter': 'all',
        'estimationConsentGiven': false,
        'themeMode': 'sepia',
      };

      final result = AppSettings.tryFrom(json);

      expect(result, isNotNull);
      expect(result!.themeMode, equals(AppThemeMode.system));
    });

    test('tryFrom(x.toJson()) round-trips default settings', () {
      const settings = AppSettings();

      expect(AppSettings.tryFrom(settings.toJson()), equals(settings));
    });

    test('tryFrom returns null when filter is missing', () {
      expect(AppSettings.tryFrom(const <String, Object?>{}), isNull);
    });

    test('tryFrom returns null when filter is an unknown name', () {
      final json = <String, Object?>{
        'filter': 'greenOnlyish',
        'estimationConsentGiven': false,
      };

      expect(AppSettings.tryFrom(json), isNull);
    });

    test('tryFrom returns null when consent is not a bool', () {
      final json = <String, Object?>{
        'filter': 'all',
        'estimationConsentGiven': 'yes',
      };

      expect(AppSettings.tryFrom(json), isNull);
    });

    test('tryFrom returns null when languageTag is not a String', () {
      final json = <String, Object?>{
        'languageTag': 7,
        'filter': 'all',
        'estimationConsentGiven': false,
      };

      expect(AppSettings.tryFrom(json), isNull);
    });

    test('tryFrom returns null when lastVenue is malformed', () {
      final json = <String, Object?>{
        'filter': 'all',
        'estimationConsentGiven': false,
        'lastVenue': <String, Object?>{'source': 'doordash'},
      };

      expect(AppSettings.tryFrom(json), isNull);
    });

    test('copyWith with no arguments returns an equal copy', () {
      const settings = AppSettings(languageTag: 'he');

      expect(settings.copyWith(), equals(settings));
    });

    test('copyWith replaces filter and consent', () {
      const settings = AppSettings();

      final result = settings.copyWith(
        filter: MenuFilter.greenOnly,
        estimationConsentGiven: true,
      );

      expect(result.filter, equals(MenuFilter.greenOnly));
      expect(result.estimationConsentGiven, isTrue);
    });

    test('copyWith omitting languageTag leaves it unchanged', () {
      const settings = AppSettings(languageTag: 'he');

      final result = settings.copyWith(filter: MenuFilter.all);

      expect(result.languageTag, equals('he'));
    });

    test('copyWith(languageTag: null) clears it', () {
      const settings = AppSettings(languageTag: 'he');

      final result = settings.copyWith(languageTag: null);

      expect(result.languageTag, isNull);
    });

    test('copyWith omitting lastVenue leaves it unchanged', () {
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const settings = AppSettings(lastVenue: ref);

      final result = settings.copyWith(filter: MenuFilter.all);

      expect(result.lastVenue, equals(ref));
    });

    test('copyWith(lastVenue: null) clears it', () {
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      const settings = AppSettings(lastVenue: ref);

      final result = settings.copyWith(lastVenue: null);

      expect(result.lastVenue, isNull);
    });

    test('copyWith replaces themeMode', () {
      const settings = AppSettings();

      final result = settings.copyWith(themeMode: AppThemeMode.dark);

      expect(result.themeMode, equals(AppThemeMode.dark));
    });

    test('copyWith omitting themeMode leaves it unchanged', () {
      const settings = AppSettings(themeMode: AppThemeMode.light);

      final result = settings.copyWith(filter: MenuFilter.all);

      expect(result.themeMode, equals(AppThemeMode.light));
    });

    test('== returns false for settings differing in themeMode', () {
      const a = AppSettings();
      const b = AppSettings(themeMode: AppThemeMode.dark);

      expect(a, isNot(equals(b)));
    });

    test('== returns true for settings with equal fields', () {
      const a = AppSettings(languageTag: 'he');
      const b = AppSettings(languageTag: 'he');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for settings differing in filter', () {
      const a = AppSettings();
      const b = AppSettings(filter: MenuFilter.greenOnly);

      expect(a, isNot(equals(b)));
    });

    test('toString mentions the language, filter and theme mode', () {
      const settings = AppSettings(
        languageTag: 'he',
        themeMode: AppThemeMode.dark,
      );

      expect(settings.toString(), contains('he'));
      expect(settings.toString(), contains('all'));
      expect(settings.toString(), contains('dark'));
    });

    group('netCarbLimitGrams (issue #57)', () {
      /// The JSON an install wrote before issue #57, plus [extra].
      Map<String, Object?> json([Map<String, Object?> extra = const {}]) =>
          <String, Object?>{
            'filter': 'all',
            'estimationConsentGiven': false,
            ...extra,
          };

      test('defaults to 6 g', () {
        expect(
          const AppSettings().netCarbLimitGrams,
          equals(defaultNetCarbLimitGrams),
        );
      });

      test('tryFrom(x.toJson()) round-trips a non-default limit', () {
        const settings = AppSettings(netCarbLimitGrams: 12);

        final result = AppSettings.tryFrom(settings.toJson());

        expect(result, equals(settings));
        expect(result!.netCarbLimitGrams, equals(12));
      });

      test('toJson writes the limit under netCarbLimitGrams', () {
        const settings = AppSettings(netCarbLimitGrams: 9);

        expect(settings.toJson()['netCarbLimitGrams'], equals(9));
      });

      test('tryFrom reads a missing limit as 6 g without invalidating '
          'the record', () {
        final result = AppSettings.tryFrom(json({'languageTag': 'he'}));

        expect(result, isNotNull);
        expect(result!.netCarbLimitGrams, equals(defaultNetCarbLimitGrams));
        expect(result.languageTag, equals('he'));
      });

      test('tryFrom reads a non-integer limit as 6 g', () {
        final asText = AppSettings.tryFrom(json({'netCarbLimitGrams': '9'}));
        final asDouble = AppSettings.tryFrom(json({'netCarbLimitGrams': 9.5}));

        expect(asText!.netCarbLimitGrams, equals(defaultNetCarbLimitGrams));
        expect(asDouble!.netCarbLimitGrams, equals(defaultNetCarbLimitGrams));
      });

      test('tryFrom clamps a limit below 2 g up to 2 g', () {
        final result = AppSettings.tryFrom(json({'netCarbLimitGrams': 0}));

        expect(result!.netCarbLimitGrams, equals(minNetCarbLimitGrams));
      });

      test('tryFrom clamps a limit above 25 g down to 25 g', () {
        final result = AppSettings.tryFrom(json({'netCarbLimitGrams': 90}));

        expect(result!.netCarbLimitGrams, equals(maxNetCarbLimitGrams));
      });

      test('tryFrom keeps both bounds exactly', () {
        final low = AppSettings.tryFrom(json({'netCarbLimitGrams': 2}));
        final high = AppSettings.tryFrom(json({'netCarbLimitGrams': 25}));

        expect(low!.netCarbLimitGrams, equals(2));
        expect(high!.netCarbLimitGrams, equals(25));
      });

      test('copyWith replaces the limit, and omitting it keeps it', () {
        const settings = AppSettings(netCarbLimitGrams: 8);

        expect(
          settings.copyWith(netCarbLimitGrams: 4).netCarbLimitGrams,
          equals(4),
        );
        expect(
          settings.copyWith(filter: MenuFilter.greenOnly).netCarbLimitGrams,
          equals(8),
        );
      });

      test('== returns false for settings differing in the limit', () {
        expect(
          const AppSettings(),
          isNot(equals(const AppSettings(netCarbLimitGrams: 7))),
        );
      });

      test('toString mentions the limit', () {
        expect(
          const AppSettings(netCarbLimitGrams: 11).toString(),
          contains('11g'),
        );
      });
    });

    group('lastFilter (issue #55)', () {
      /// The JSON an install wrote before issue #55, plus [extra].
      Map<String, Object?> json([Map<String, Object?> extra = const {}]) =>
          <String, Object?>{
            'filter': 'all',
            'estimationConsentGiven': false,
            ...extra,
          };

      test('defaults to null', () {
        expect(const AppSettings().lastFilter, isNull);
      });

      test('tryFrom(x.toJson()) round-trips every MenuFilter value', () {
        for (final filter in MenuFilter.values) {
          final settings = AppSettings(lastFilter: filter);

          expect(AppSettings.tryFrom(settings.toJson()), equals(settings));
        }
      });

      test('toJson writes the filter name under lastFilter', () {
        const settings = AppSettings(lastFilter: MenuFilter.yellowOnly);

        expect(settings.toJson()['lastFilter'], equals('yellowOnly'));
      });

      test('toJson writes null when unset', () {
        expect(const AppSettings().toJson()['lastFilter'], isNull);
      });

      test('tryFrom reads a missing lastFilter as null without '
          'invalidating the record', () {
        final result = AppSettings.tryFrom(json({'languageTag': 'he'}));

        expect(result, isNotNull);
        expect(result!.lastFilter, isNull);
        expect(result.languageTag, equals('he'));
      });

      test('tryFrom reads an unrecognised lastFilter as null rather than '
          'invalidating the whole record', () {
        final result = AppSettings.tryFrom(
          json({'lastFilter': 'greenOnlyish'}),
        );

        expect(result, isNotNull);
        expect(result!.lastFilter, isNull);
      });

      test('copyWith replaces lastFilter, and omitting it keeps it', () {
        const settings = AppSettings(lastFilter: MenuFilter.redOnly);

        expect(
          settings.copyWith(lastFilter: MenuFilter.greenOnly).lastFilter,
          equals(MenuFilter.greenOnly),
        );
        expect(
          settings.copyWith(filter: MenuFilter.all).lastFilter,
          equals(MenuFilter.redOnly),
        );
      });

      test('copyWith(lastFilter: null) clears it', () {
        const settings = AppSettings(lastFilter: MenuFilter.redOnly);

        expect(settings.copyWith(lastFilter: null).lastFilter, isNull);
      });

      test('== returns false for settings differing only in lastFilter', () {
        expect(
          const AppSettings(),
          isNot(equals(const AppSettings(lastFilter: MenuFilter.redOnly))),
        );
      });

      test('toString mentions lastFilter', () {
        expect(
          const AppSettings(lastFilter: MenuFilter.redOnly).toString(),
          contains('redOnly'),
        );
      });
    });
  });

  group('ChatCompleted', () {
    test('== returns true for equal results', () {
      const a = ChatCompleted(content: '{}', model: 'm1');
      const b = ChatCompleted(content: '{}', model: 'm1');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for results differing in model', () {
      const a = ChatCompleted(content: '{}', model: 'm1');
      const b = ChatCompleted(content: '{}', model: 'm2');

      expect(a, isNot(equals(b)));
    });

    test('toString mentions the model', () {
      const result = ChatCompleted(content: '{}', model: 'm1');

      expect(result.toString(), contains('m1'));
    });
  });

  group('ChatFailed', () {
    test('== returns true for equal failures', () {
      const a = ChatFailed(
        reason: ChatFailureReason.rateLimited,
        statusCode: 429,
      );
      const b = ChatFailed(
        reason: ChatFailureReason.rateLimited,
        statusCode: 429,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for failures differing in statusCode', () {
      const a = ChatFailed(reason: ChatFailureReason.badResponse);
      const b = ChatFailed(
        reason: ChatFailureReason.badResponse,
        statusCode: 500,
      );

      expect(a, isNot(equals(b)));
    });

    test('statusCode is null when the reason carries no HTTP status', () {
      const result = ChatFailed(reason: ChatFailureReason.offline);

      expect(result.statusCode, isNull);
    });

    test('toString mentions the reason', () {
      const result = ChatFailed(reason: ChatFailureReason.backendUnreachable);

      expect(result.toString(), contains('backendUnreachable'));
    });
  });

  runMenuCacheContract('FakeMenuCache', FakeMenuCache.new);
  runSettingsStoreContract('FakeSettingsStore', FakeSettingsStore.new);
  runLlmChatClientContract('FakeLlmChatClient', FakeLlmChatClient.new);
  runInstallIdStoreContract('FakeInstallIdStore', FakeInstallIdStore.new);
  runNotesStoreContract('FakeNotesStore', FakeNotesStore.new);

  group('FakeMenuCache degradation switches', () {
    test('failOnRead makes every read miss without throwing', () async {
      final cache = FakeMenuCache();
      final cachedMenu = _cachedMenuFixture();
      await cache.write(cachedMenu);

      cache.failOnRead = true;

      expect(await cache.read(cachedMenu.menu.venueRef), isNull);
    });

    test('failOnWrite drops the write without throwing', () async {
      final cache = FakeMenuCache()..failOnWrite = true;
      final cachedMenu = _cachedMenuFixture();

      await cache.write(cachedMenu);

      expect(await cache.read(cachedMenu.menu.venueRef), isNull);
    });
  });
}

/// A venue ref shared by this file's `CachedMenu` value-object tests.
const VenueRef _woltRef = VenueRef(source: MenuSource.wolt, platformId: 'x');

/// A minimal cached-menu fixture, local to this file's degradation
/// tests, distinct from the shared one in `menu_cache_contract.dart`.
CachedMenu _cachedMenuFixture() => CachedMenu(menu: _menuFor(_woltRef));

/// A minimal [Menu] for [ref], with no categories, local to this file's
/// `CachedMenu` value-object tests.
Menu _menuFor(VenueRef ref) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[],
);
