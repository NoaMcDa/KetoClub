import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/constants.dart';

import '../services/classifier/scanned_menu_classifier_contract.dart';
import '../services/llm/llm_chat_client_contract.dart';
import '../services/platform/page_picker_contract.dart';
import '../services/platform/qr_scanner_contract.dart';
import '../services/storage/api_key_store_contract.dart';
import '../services/storage/install_id_store_contract.dart';
import '../services/storage/menu_cache_contract.dart';
import '../services/storage/notes_store_contract.dart';
import '../services/storage/settings_store_contract.dart';
import 'fake_api_key_store.dart';
import 'fake_app_logger.dart';
import 'fake_clock.dart';
import 'fake_install_id_store.dart';
import 'fake_llm_chat_client.dart';
import 'fake_menu_cache.dart';
import 'fake_notes_store.dart';
import 'fake_page_picker.dart';
import 'fake_qr_scanner.dart';
import 'fake_scanned_menu_classifier.dart';
import 'fake_settings_store.dart';

void main() {
  group('FakeClock', () {
    test('advance moves now forward by the given duration', () {
      final clock = FakeClock(DateTime.utc(2026))
        ..advance(const Duration(days: 1, hours: 2));

      expect(clock.now(), equals(DateTime.utc(2026, 1, 2, 2)));
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
      expect(recorded.images, isEmpty);
    });

    test('complete records the images it was sent, in order', () async {
      final client = FakeLlmChatClient();
      final page1 = ChatImagePart(
        mimeType: ChatImagePart.jpeg,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final page2 = ChatImagePart(
        mimeType: ChatImagePart.pdf,
        bytes: Uint8List.fromList(<int>[4]),
      );

      await client.complete(
        systemPrompt: 'system',
        userPrompt: 'user',
        images: <ChatImagePart>[page1, page2],
      );

      expect(client.requests.single.images, orderedEquals([page1, page2]));
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
    test('defaults are all filter, consent on (D16, issue #167), no '
        'venue, no language, system appearance, disclosure unseen', () {
      const settings = AppSettings();

      expect(settings.languageTag, isNull);
      expect(settings.filter, equals(MenuFilter.all));
      expect(settings.estimationConsentGiven, isTrue);
      expect(settings.disclosureSeen, isFalse);
      expect(settings.lastVenue, isNull);
      expect(settings.themeMode, equals(AppThemeMode.system));
    });

    test('tryFrom(x.toJson()) round-trips settings with every field set', () {
      // D16 (issue #167) flipped estimationConsentGiven's default to
      // true; this round-trip exercises the non-default (false).
      const settings = AppSettings(
        languageTag: 'he',
        filter: MenuFilter.greenOnly,
        estimationConsentGiven: false,
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
      // D16 (issue #167): defaults are all filter and consent on.
      // Exercise replacing them both with the non-defaults.
      const settings = AppSettings();

      final result = settings.copyWith(
        filter: MenuFilter.greenOnly,
        estimationConsentGiven: false,
      );

      expect(result.filter, equals(MenuFilter.greenOnly));
      expect(result.estimationConsentGiven, isFalse);
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

    group('netCarbLimitGrams (issue #57)', () {
      /// The JSON an install wrote before issue #57, plus [extra].
      Map<String, Object?> json([Map<String, Object?> extra = const {}]) =>
          <String, Object?>{
            'filter': 'all',
            'estimationConsentGiven': false,
            ...extra,
          };

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
    });

    group('lastFilter (issue #55)', () {
      /// The JSON an install wrote before issue #55, plus [extra].
      Map<String, Object?> json([Map<String, Object?> extra = const {}]) =>
          <String, Object?>{
            'filter': 'all',
            'estimationConsentGiven': false,
            ...extra,
          };

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
    });
  });

  runMenuCacheContract('FakeMenuCache', FakeMenuCache.new);
  runSettingsStoreContract('FakeSettingsStore', FakeSettingsStore.new);
  runLlmChatClientContract('FakeLlmChatClient', FakeLlmChatClient.new);
  runInstallIdStoreContract('FakeInstallIdStore', FakeInstallIdStore.new);
  runNotesStoreContract('FakeNotesStore', FakeNotesStore.new);
  runApiKeyStoreContract('FakeApiKeyStore', FakeApiKeyStore.new);
  runScannedMenuClassifierContract(
    'FakeScannedMenuClassifier',
    FakeScannedMenuClassifier.new,
    recordedOptions: (fake) => [for (final call in fake.calls) call.$2],
  );
  runPagePickerContract('FakePagePicker', FakePagePicker.new);
  runQrScannerContract('FakeQrScanner', FakeQrScanner.new);

  group('FakeScannedMenuClassifier', () {
    test('reads one dish per page under a scan reference by default', () async {
      // Arrange
      final fake = FakeScannedMenuClassifier();

      // Act
      final result = await fake.classify(
        _scanOf(2),
        options: const ClassificationOptions(),
      );

      // Assert
      final read = result as ScannedMenuRead;
      expect(read.menu.venueRef.source, equals(MenuSource.scan));
      expect(
        read.menu.allDishes.map((dish) => dish.name),
        equals(<String>['Scanned dish 1', 'Scanned dish 2']),
      );
      expect(read.analysis.engine, equals(fake.derivedEngine));
      expect(
        read.analysis.dishes.map((dish) => dish.why).toSet(),
        equals(<String>{FakeScannedMenuClassifier.defaultWhy}),
      );
    });

    test('answers noDishesFound for a scan with no pages', () async {
      final result = await FakeScannedMenuClassifier().classify(
        _scanOf(0),
        options: const ClassificationOptions(),
      );

      expect(
        result,
        equals(
          const ScannedMenuFailed(
            reason: MenuAnalysisFailureReason.noDishesFound,
          ),
        ),
      );
    });

    test('respondWith scripts every later call', () async {
      // Arrange
      const scripted = ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.offline,
      );
      final fake = FakeScannedMenuClassifier()..respondWith(scripted);

      // Act
      final first = await fake.classify(
        _scanOf(1),
        options: const ClassificationOptions(),
      );
      final second = await fake.classify(
        _scanOf(3),
        options: const ClassificationOptions(),
      );

      // Assert
      expect(first, equals(scripted));
      expect(second, equals(scripted));
      expect(fake.calls.map((call) => call.$1.pages.length), equals([1, 3]));
    });

    test('announces its engines and waits for its gate', () async {
      // Arrange
      final heard = <ClassifyingEngine>[];
      final gate = Completer<void>();
      final fake = FakeScannedMenuClassifier()
        ..announces = const <ClassifyingEngine>[ClassifyingEngine.llm]
        ..gate = gate.future;
      var done = false;

      // Act
      final pending = fake
          .classify(
            _scanOf(1),
            options: ClassificationOptions(onEngineStarted: heard.add),
          )
          .then((_) => done = true);
      await Future<void>.delayed(Duration.zero);

      // Assert: announced, still held open, then released.
      expect(heard, equals(<ClassifyingEngine>[ClassifyingEngine.llm]));
      expect(done, isFalse);
      gate.complete();
      await pending;
      expect(done, isTrue);
    });
  });

  group('FakePagePicker', () {
    test('has a camera unless told otherwise', () {
      expect(FakePagePicker().canTakePhoto, isTrue);
      expect(FakePagePicker(canTakePhoto: false).canTakePhoto, isFalse);
    });

    test('answers each method from its own queue, then as cancelled', () async {
      // Arrange
      final photo = _pageOf(1);
      final image = _pageOf(2);
      final pdf = ScannedPage(
        mimeType: ScannedPage.pdf,
        bytes: Uint8List.fromList(<int>[3]),
      );
      final picker = FakePagePicker()
        ..queueTakePhoto(<ScannedPage>[photo])
        ..queuePickImages(<ScannedPage>[image, photo])
        ..queuePickPdf(<ScannedPage>[pdf]);

      // Act / Assert
      expect(await picker.takePhoto(), equals(<ScannedPage>[photo]));
      expect(await picker.pickImages(), equals(<ScannedPage>[image, photo]));
      expect(await picker.pickPdf(), equals(<ScannedPage>[pdf]));
      expect(await picker.takePhoto(), isEmpty);
      expect(await picker.pickImages(), isEmpty);
      expect(await picker.pickPdf(), isEmpty);
    });

    test('records every call in order', () async {
      final picker = FakePagePicker();

      await picker.pickPdf();
      await picker.takePhoto();
      await picker.pickImages();

      expect(
        picker.calls,
        equals(<PagePickerCall>[
          PagePickerCall.pickPdf,
          PagePickerCall.takePhoto,
          PagePickerCall.pickImages,
        ]),
      );
    });
  });

  group('FakeQrScanner', () {
    test('answers queued payloads in order, then null, and counts', () async {
      // Arrange
      final scanner = FakeQrScanner()
        ..queuePayload('https://a.example/menu')
        ..queuePayload(null)
        ..queuePayload('second');

      // Act / Assert
      expect(await scanner.scan(), 'https://a.example/menu');
      expect(await scanner.scan(), isNull);
      expect(await scanner.scan(), 'second');
      expect(await scanner.scan(), isNull);
      expect(scanner.scanCallCount, 4);
    });
  });

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

/// A one-byte JPEG page holding [seed], for the scan fakes' tests.
ScannedPage _pageOf(int seed) => ScannedPage(
  mimeType: ScannedPage.jpeg,
  bytes: Uint8List.fromList(<int>[seed]),
);

/// A scan of [count] distinct pages, for the scan fakes' tests.
ScannedMenu _scanOf(int count) => ScannedMenu(
  pages: <ScannedPage>[for (var i = 0; i < count; i++) _pageOf(i)],
);

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
