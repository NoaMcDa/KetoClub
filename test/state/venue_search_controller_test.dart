import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';

import '../fakes/fake_location_service.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_venue_search_service.dart';

/// A Wolt venue addressed by [slug], with the card fields a test sets.
Venue _venue(
  String slug, {
  List<String> tags = const <String>[],
  bool? isOnline,
  double? latitude,
  double? longitude,
}) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: slug,
  cuisineTags: tags,
  isOnline: isOnline,
  latitude: latitude,
  longitude: longitude,
);

/// A cached menu for [ref] whose analysis placed [green], [yellow] and
/// [red] dishes, produced by [engine].
CachedMenu _analysed(
  VenueRef ref, {
  required int green,
  required int yellow,
  required int red,
  AnalysisEngine engine = const LlmEngine(model: 'test-model'),
}) {
  AnalysedDish dish(int i, DishVerdict verdict) => AnalysedDish(
    dishId: '$i',
    name: 'Dish $i',
    verdict: verdict,
    why: 'why',
    modification: verdict == DishVerdict.modifiable ? 'swap' : null,
  );
  var i = 0;
  return CachedMenu(
    menu: Menu(
      venueRef: ref,
      currency: 'ILS',
      fetchedAt: DateTime.utc(2026),
      categories: const <MenuCategory>[],
    ),
    analysis: MenuAnalysed(
      dishes: [
        for (var n = 0; n < green; n++) dish(i++, DishVerdict.orderAsIs),
        for (var n = 0; n < yellow; n++) dish(i++, DishVerdict.modifiable),
        for (var n = 0; n < red; n++) dish(i++, DishVerdict.nonKeto),
      ],
      unclassified: const <String>[],
      engine: engine,
      analysedAt: DateTime.utc(2026),
    ),
  );
}

void main() {
  group('VenueSearchController', () {
    late FakeSettingsStore settings;
    late FakeMenuRepository repository;
    late FakeLocationService location;
    late FakeVenueSearchService search;
    late VenueSearchController controller;

    VenueSearchController build() => VenueSearchController(
      settings,
      repository,
      locationService: location,
      venueSearchService: search,
    );

    setUp(() {
      settings = FakeSettingsStore();
      repository = FakeMenuRepository();
      location = FakeLocationService();
      search = FakeVenueSearchService();
      controller = build();
    });

    tearDown(() => controller.dispose());

    group('paste path (unchanged)', () {
      test('setInput with a Wolt url resolves to a wolt VenueRef', () {
        // Arrange
        const url = 'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina';

        // Act
        controller.setInput(url);

        // Assert
        expect(
          controller.resolved,
          const VenueRef(source: MenuSource.wolt, platformId: 'vitrina'),
        );
        expect(controller.isInvalid, isFalse);
      });

      test('setInput with a bare slug resolves to MenuSource.wolt', () {
        // Arrange
        const slug = 'vitrina-lilinblum';

        // Act
        controller.setInput(slug);

        // Assert
        expect(controller.resolved?.source, MenuSource.wolt);
        expect(controller.resolved?.platformId, slug);
      });

      test('setInput with a numeric id resolves to MenuSource.tenbis', () {
        // Arrange
        const id = '123456';

        // Act
        controller.setInput(id);

        // Assert
        expect(controller.resolved?.source, MenuSource.tenbis);
        expect(controller.resolved?.platformId, id);
      });

      test('setInput with nonsense sets isInvalid true', () {
        // Arrange
        const nonsense = 'https://example.com/not/a/venue';

        // Act
        controller.setInput(nonsense);

        // Assert
        expect(controller.resolved, isNull);
        expect(controller.isInvalid, isTrue);
      });

      test('setInput with empty input is neither resolved nor invalid', () {
        // Act
        controller.setInput('');

        // Assert
        expect(controller.resolved, isNull);
        expect(controller.isInvalid, isFalse);
        expect(controller.input, '');
      });

      test('setInput notifies listeners exactly once per call', () {
        // Arrange
        var notifyCount = 0;

        // Act
        controller
          ..addListener(() => notifyCount++)
          ..setInput('vitrina-lilinblum')
          ..setInput('123456')
          ..setInput('');

        // Assert
        expect(notifyCount, 3);
      });

      test('a pasted link wins: search never reaches the search service', () {
        fakeAsync((async) {
          // Act
          controller.search(
            'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina',
            language: 'en',
          );
          async.elapse(const Duration(seconds: 1));

          // Assert
          expect(controller.isPaste, isTrue);
          expect(controller.resolved?.platformId, 'vitrina');
          expect(search.byNameCalls, isEmpty);
        });
      });

      test('a pasted 10bis id is a paste, not a name to search', () {
        fakeAsync((async) {
          // Act
          controller.search('123456', language: 'en');
          async.elapse(const Duration(seconds: 1));

          // Assert
          expect(controller.isPaste, isTrue);
          expect(search.byNameCalls, isEmpty);
        });
      });

      test('a bare word is searched by name and still resolves as a slug', () {
        fakeAsync((async) {
          // Act
          controller.search('vitrina', language: 'en');
          async.elapse(venueSearchDebounce);

          // Assert
          expect(controller.isPaste, isFalse);
          expect(controller.resolved?.platformId, 'vitrina');
          expect(search.byNameCalls.single.query, 'vitrina');
        });
      });
    });

    group('lastVenue (issue #55)', () {
      test('load leaves lastVenue null when nothing has been opened', () async {
        // Act
        await controller.load();

        // Assert
        expect(controller.lastVenue, isNull);
        expect(controller.lastVenueName, isNull);
      });

      test('load exposes AppSettings.lastVenue and its cached name', () async {
        // Arrange
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
        await settings.write(const AppSettings(lastVenue: ref));
        repository.seedCache(
          CachedMenu(
            menu: Menu(
              venueRef: ref,
              venueName: 'Vitrina',
              currency: 'ILS',
              fetchedAt: DateTime.utc(2026),
              categories: const <MenuCategory>[],
            ),
          ),
        );

        // Act
        await controller.load();

        // Assert
        expect(controller.lastVenue, equals(ref));
        expect(controller.lastVenueName, equals('Vitrina'));
      });

      test('load falls back to the platform id when nothing is cached for '
          'it', () async {
        // Arrange
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
        await settings.write(const AppSettings(lastVenue: ref));

        // Act
        await controller.load();

        // Assert
        expect(controller.lastVenueName, equals('vitrina'));
      });

      test('load notifies listeners exactly once', () async {
        // Arrange
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        // Act
        await controller.load();

        // Assert
        expect(notifyCount, 1);
      });
    });

    group('locate', () {
      test('a found position lists the venues nearby in the given '
          'language', () async {
        // Arrange
        search.queueFound([_venue('a'), _venue('b')]);

        // Act
        await controller.locate(language: 'he');

        // Assert
        final call = search.nearbyCalls.single;
        expect(call.latitude, 32.0809);
        expect(call.longitude, 34.7806);
        expect(call.language, 'he');
        expect(controller.locationOutcome, isA<LocationFound>());
        expect(controller.position?.latitude, 32.0809);
        expect(controller.results.map((v) => v.name), ['a', 'b']);
        expect(controller.hasSearched, isTrue);
        expect(controller.phase, DiscoveryPhase.idle);
        expect(controller.failure, isNull);
      });

      test('passes through locating and searching on the way', () async {
        // Arrange
        final phases = <DiscoveryPhase>[];
        controller.addListener(() => phases.add(controller.phase));

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(phases.first, DiscoveryPhase.locating);
        expect(phases, contains(DiscoveryPhase.searching));
        expect(phases.last, DiscoveryPhase.idle);
      });

      test('a denial is kept as the outcome and searches nothing', () async {
        // Arrange
        location.result = const LocationDenied(permanently: true);

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(
          controller.locationOutcome,
          const LocationDenied(permanently: true),
        );
        expect(controller.position, isNull);
        expect(search.nearbyCalls, isEmpty);
        expect(controller.hasSearched, isFalse);
        expect(controller.phase, DiscoveryPhase.idle);
      });

      test('an unavailable location is kept with its reason', () async {
        // Arrange
        location.result = const LocationUnavailable(
          reason: LocationUnavailableReason.timeout,
        );

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(
          controller.locationOutcome,
          const LocationUnavailable(reason: LocationUnavailableReason.timeout),
        );
        expect(search.nearbyCalls, isEmpty);
        expect(controller.phase, DiscoveryPhase.idle);
      });

      test('a failed search exposes its reason and retry asks again', () async {
        // Arrange
        search
          ..queueFailed(VenueSearchFailureReason.rateLimited)
          ..queueFound([_venue('a')]);

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(controller.failure, VenueSearchFailureReason.rateLimited);
        expect(controller.results, isEmpty);

        // Act
        await controller.retry();

        // Assert
        expect(search.nearbyCalls, hasLength(2));
        expect(controller.failure, isNull);
        expect(controller.results.single.name, 'a');
      });

      test('retry before any search does nothing', () async {
        // Act
        await controller.retry();

        // Assert
        expect(search.nearbyCalls, isEmpty);
        expect(search.byNameCalls, isEmpty);
      });
    });

    group('search by name', () {
      test('waits for the debounce, then searches only the last text', () {
        fakeAsync((async) {
          // Act: three keystrokes inside one debounce window.
          controller
            ..search('s', language: 'en')
            ..search('su', language: 'en')
            ..search('sushi', language: 'en');
          async.elapse(venueSearchDebounce - const Duration(milliseconds: 1));

          // Assert: nothing yet.
          expect(search.byNameCalls, isEmpty);

          // Act
          async.elapse(const Duration(milliseconds: 1));

          // Assert
          expect(search.byNameCalls.single.query, 'sushi');
          expect(search.byNameCalls.single.language, 'en');
        });
      });

      test('immediate searches at once, with no debounce', () async {
        // Arrange
        search.queueFound([_venue('sushi-bar')]);

        // Act
        controller.search('sushi', language: 'he', immediate: true);
        await pumpEventQueue();

        // Assert
        expect(search.byNameCalls.single.language, 'he');
        expect(controller.results.single.name, 'sushi-bar');
      });

      test('ranks by the located position once there is one', () async {
        // Arrange
        await controller.locate(language: 'en');

        // Act
        controller.search('sushi', language: 'en', immediate: true);
        await pumpEventQueue();

        // Assert
        final call = search.byNameCalls.single;
        expect(call.latitude, 32.0809);
        expect(call.longitude, 34.7806);
      });

      test('the debounce is injectable', () {
        fakeAsync((async) {
          // Arrange
          controller.dispose();
          controller =
              VenueSearchController(
                  settings,
                  repository,
                  locationService: location,
                  venueSearchService: search,
                  debounce: const Duration(seconds: 2),
                )
                // Act
                ..search('sushi', language: 'en');
          async.elapse(venueSearchDebounce);

          // Assert
          expect(search.byNameCalls, isEmpty);
          async.elapse(const Duration(seconds: 2));
          expect(search.byNameCalls, hasLength(1));
        });
      });

      test('a search that finds nothing is told apart from none asked', () {
        fakeAsync((async) {
          // Assert: nothing asked yet.
          expect(controller.hasSearched, isFalse);

          // Act
          controller.search('nothing-here', language: 'en');
          async
            ..elapse(venueSearchDebounce)
            ..flushMicrotasks();

          // Assert
          expect(controller.hasSearched, isTrue);
          expect(controller.results, isEmpty);
        });
      });

      test('clearing the search puts the nearby list back without a new '
          'request', () async {
        // Arrange
        search
          ..queueFound([_venue('near')])
          ..queueFound([_venue('named')]);
        await controller.locate(language: 'en');
        controller.search('named', language: 'en', immediate: true);
        await pumpEventQueue();
        expect(controller.results.single.name, 'named');

        // Act
        controller.clearSearch();

        // Assert
        expect(controller.input, isEmpty);
        expect(controller.results.single.name, 'near');
        expect(search.nearbyCalls, hasLength(1));
        expect(search.byNameCalls, hasLength(1));
      });

      test('clearing with no nearby list goes back to nothing asked', () async {
        // Arrange
        search.queueFound([_venue('named')]);
        controller.search('named', language: 'en', immediate: true);
        await pumpEventQueue();

        // Act
        controller.clearSearch();

        // Assert
        expect(controller.results, isEmpty);
        expect(controller.hasSearched, isFalse);
      });

      test('a blank query cancels a pending search', () {
        fakeAsync((async) {
          // Act
          controller
            ..search('sushi', language: 'en')
            ..search('', language: 'en');
          async.elapse(const Duration(seconds: 1));

          // Assert
          expect(search.byNameCalls, isEmpty);
        });
      });

      test('dispose cancels a pending search', () {
        fakeAsync((async) {
          // Act
          controller
            ..search('sushi', language: 'en')
            ..dispose();
          async.elapse(const Duration(seconds: 1));

          // Assert
          expect(search.byNameCalls, isEmpty);

          // Re-create so tearDown's dispose has a live controller.
          controller = build();
        });
      });
    });

    group('chips', () {
      final grill = _venue('grill', tags: ['grill'], isOnline: true);
      final sushi = _venue('sushi', tags: ['sushi', 'grill'], isOnline: false);
      final cafe = _venue('cafe', tags: ['cafe']);

      Future<void> list(List<Venue> venues) async {
        search.queueFound(venues);
        await controller.locate(language: 'en');
      }

      test('nearby is the default and shows every result', () async {
        // Act
        await list([grill, sushi, cafe]);

        // Assert
        expect(controller.activeChip, DiscoveryChip.nearby);
        expect(controller.visibleResults, [grill, sushi, cafe]);
      });

      test('open now keeps only venues the platform says are online', () async {
        // Arrange
        await list([grill, sushi, cafe]);

        // Act
        controller.selectChip(DiscoveryChip.openNow);

        // Assert
        expect(controller.visibleResults, [grill]);
      });

      test('topCuisine is the most common tag and the cuisine chip keeps '
          'it', () async {
        // Arrange
        await list([grill, sushi, cafe]);

        // Act
        controller.selectChip(DiscoveryChip.cuisine);

        // Assert
        expect(controller.topCuisine, 'grill');
        expect(controller.visibleResults, [grill, sushi]);
      });

      test('topCuisine is null when no result has a tag', () async {
        // Act
        await list([_venue('plain')]);

        // Assert
        expect(controller.topCuisine, isNull);
      });

      test('tapping the active chip again goes back to nearby', () async {
        // Arrange
        await list([grill, sushi, cafe]);

        // Act: the same chip, twice.
        controller
          ..selectChip(DiscoveryChip.openNow)
          ..selectChip(DiscoveryChip.openNow);

        // Assert
        expect(controller.activeChip, DiscoveryChip.nearby);
        expect(controller.visibleResults, hasLength(3));
      });

      test('keto 8+ keeps scores of 8.0 and above only', () async {
        // Arrange: 8.0 exactly (8 green, 2 red), 7.5 (5 green, 5 yellow).
        repository
          ..seedCache(_analysed(grill.ref, green: 8, yellow: 0, red: 2))
          ..seedCache(_analysed(sushi.ref, green: 5, yellow: 5, red: 0));
        await list([grill, sushi, cafe]);

        // Act
        controller.selectChip(DiscoveryChip.ketoEightPlus);

        // Assert
        expect(controller.cardNumbers(grill)?.score, 8.0);
        expect(controller.cardNumbers(sushi)?.score, 7.5);
        expect(controller.visibleResults, [grill]);
      });

      test('a new result set resets the chip to nearby', () async {
        // Arrange
        await list([grill, sushi]);
        controller.selectChip(DiscoveryChip.openNow);

        // Act
        await list([cafe]);

        // Assert
        expect(controller.activeChip, DiscoveryChip.nearby);
      });
    });

    group('card numbers (D13)', () {
      final venue = _venue('vitrina');

      test('come from a cached MenuAnalysed', () async {
        // Arrange
        repository.seedCache(_analysed(venue.ref, green: 9, yellow: 5, red: 2));
        search.queueFound([venue]);

        // Act
        await controller.locate(language: 'en');

        // Assert
        final numbers = controller.cardNumbers(venue);
        expect(numbers?.green, 9);
        expect(numbers?.yellow, 5);
        expect(numbers?.score, 7.2);
        expect(numbers?.engine, isA<LlmEngine>());
        expect(controller.hasAnyNumbers, isTrue);
      });

      test('carry a rules engine through for the estimate marker', () async {
        // Arrange
        repository.seedCache(
          _analysed(
            venue.ref,
            green: 1,
            yellow: 0,
            red: 0,
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.offline,
            ),
          ),
        );
        search.queueFound([venue]);

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(controller.cardNumbers(venue)?.engine, isA<RulesEngine>());
      });

      test(
        'are null with nothing cached, and Keto 8+ is not offered',
        () async {
          // Arrange
          search.queueFound([venue]);

          // Act
          await controller.locate(language: 'en');

          // Assert
          expect(controller.cardNumbers(venue), isNull);
          expect(controller.hasAnyNumbers, isFalse);
        },
      );

      test('are null for a cached menu with no analysis, or one that placed '
          'no dish', () async {
        // Arrange
        final empty = _venue('empty');
        repository
          ..seedCache(
            CachedMenu(
              menu: Menu(
                venueRef: venue.ref,
                currency: 'ILS',
                fetchedAt: DateTime.utc(2026),
                categories: const <MenuCategory>[],
              ),
            ),
          )
          ..seedCache(_analysed(empty.ref, green: 0, yellow: 0, red: 0));
        search.queueFound([venue, empty]);

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(controller.cardNumbers(venue), isNull);
        expect(controller.cardNumbers(empty), isNull);
      });

      test('never fetch a menu or touch a classifier', () async {
        // Arrange: a classifier fake exists and is never handed to the
        // controller — the assertion is that nothing in this flow could
        // reach one, and that the repository is only ever read.
        final classifier = FakeMenuClassifier();
        repository.seedCache(_analysed(venue.ref, green: 3, yellow: 1, red: 1));
        search
          ..queueFound([venue, _venue('other')])
          ..queueFound([venue]);

        // Act: locate, search, filter, clear — everything the screen can
        // make the controller do.
        await controller.locate(language: 'en');
        controller
          ..selectChip(DiscoveryChip.ketoEightPlus)
          ..selectChip(DiscoveryChip.openNow)
          ..search('vitrina', language: 'en', immediate: true);
        await pumpEventQueue();
        controller.clearSearch();
        await controller.retry();
        controller.results.forEach(controller.cardNumbers);

        // Assert
        expect(repository.loadCalls, isEmpty);
        expect(repository.savedAnalyses, isEmpty);
        expect(classifier.calls, isEmpty);
      });
    });

    group('distanceKmTo', () {
      test('is null before a position is known', () {
        // Assert
        expect(
          controller.distanceKmTo(
            _venue('a', latitude: 32.08, longitude: 34.78),
          ),
          isNull,
        );
      });

      test('measures from the located position', () async {
        // Arrange
        await controller.locate(language: 'en');

        // Act
        final km = controller.distanceKmTo(
          _venue('a', latitude: 32.0809, longitude: 34.7806),
        );

        // Assert
        expect(km, closeTo(0, 0.001));
        expect(controller.distanceKmTo(_venue('b')), isNull);
      });
    });
  });
}
