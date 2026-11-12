import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/place/place_search_service.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/known_places.dart';
import 'package:ketoclub/utils/venue_route.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_place_search_service.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_venue_search_service.dart';
import '../fakes/fake_visit_history_store.dart';

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

/// A fetched menu for [ref] holding one dish, so a classifier has
/// something to place.
MenuFetched _fetchedWithOneDish(VenueRef ref) => MenuFetched(
  menu: Menu(
    venueRef: ref,
    currency: 'ILS',
    fetchedAt: DateTime.utc(2026),
    categories: const <MenuCategory>[
      MenuCategory(
        id: 'mains',
        name: 'Mains',
        dishes: <Dish>[
          Dish(
            id: 'steak',
            name: 'Steak',
            description: '',
            price: 80,
            options: <DishOption>[],
          ),
        ],
      ),
    ],
  ),
);

void main() {
  group('VenueSearchController', () {
    late FakeSettingsStore settings;
    late FakeMenuRepository repository;
    late FakeLocationService location;
    late FakeVenueSearchService search;
    late FakeMenuClassifier estimator;
    late FakeVisitHistoryStore history;
    late VenueSearchController controller;

    /// A controller with the automatic quick score (D21) off unless
    /// [autoEstimateLimit] says otherwise, so every group but the one
    /// about that run sees only the fetches it asks for.
    VenueSearchController build({int autoEstimateLimit = 0}) =>
        VenueSearchController(
          settings,
          repository,
          locationService: location,
          venueSearchService: search,
          estimateClassifier: estimator,
          autoEstimateLimit: autoEstimateLimit,
          visitHistory: history,
        );

    setUp(() {
      settings = FakeSettingsStore();
      repository = FakeMenuRepository();
      location = FakeLocationService();
      search = FakeVenueSearchService();
      estimator = FakeMenuClassifier();
      history = FakeVisitHistoryStore(FakeClock(DateTime.utc(2026)));
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
        // A Wolt page that is not a venue: Wolt keeps priority over the
        // website source (D19), so this is unreadable, not a website.
        const nonsense = 'https://wolt.com/en/discovery';

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

      test('a bare word is searched by name, no longer resolved as a slug '
          '(issue #169)', () {
        fakeAsync((async) {
          // Act
          controller.search('vitrina', language: 'en');
          async.elapse(venueSearchDebounce);

          // Assert: a bare word no longer resolves as a Wolt slug — a
          // hyphenated shape is required now, so `VenueRefResolver` no
          // longer offers "Show the keto menu" for it. The by-name
          // search still fires regardless.
          expect(controller.isPaste, isFalse);
          expect(controller.resolved, isNull);
          expect(search.byNameCalls.single.query, 'vitrina');
        });
      });

      test('isExplicitLink is true for a link or id, false for a word', () {
        // Act and assert
        controller.setInput('https://wolt.com/en/isr/tel-aviv/restaurant/v');
        expect(controller.isExplicitLink, isTrue);
        controller.setInput('123456');
        expect(controller.isExplicitLink, isTrue);
        controller.setInput('pizza');
        expect(controller.isExplicitLink, isFalse);
        controller.setInput('vitrina-lilinblum');
        expect(controller.isExplicitLink, isFalse);
        controller.setInput('a/b');
        expect(controller.isExplicitLink, isFalse);
        controller.setInput('');
        expect(controller.isExplicitLink, isFalse);
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
        // The fallback is for showing, never for passing on (issue #312).
        expect(controller.lastVenueHint, const VenueOpenHint());
      });

      test('load names the last venue from the visit history before the '
          'cache, with its city (issue #312)', () async {
        // Arrange
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
        await settings.write(const AppSettings(lastVenue: ref));
        repository.seedCache(
          CachedMenu(
            menu: Menu(
              venueRef: ref,
              venueName: 'Cached Name',
              currency: 'ILS',
              fetchedAt: DateTime.utc(2026),
              categories: const <MenuCategory>[],
            ),
          ),
        );
        history.seed(
          VisitEntry(
            ref: ref,
            name: 'Vitrina',
            city: 'Tel Aviv',
            firstOpenedAt: DateTime.utc(2026),
            lastOpenedAt: DateTime.utc(2026),
            openCount: 1,
          ),
        );

        // Act
        await controller.load();

        // Assert
        expect(controller.lastVenueName, 'Vitrina');
        expect(
          controller.lastVenueHint,
          const VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv'),
        );
      });

      test('load falls back to the cached name when the visit history '
          'names none, keeping the history city (issue #312)', () async {
        // Arrange
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
        await settings.write(const AppSettings(lastVenue: ref));
        repository.seedCache(
          CachedMenu(
            menu: Menu(
              venueRef: ref,
              venueName: 'Cached Name',
              currency: 'ILS',
              fetchedAt: DateTime.utc(2026),
              categories: const <MenuCategory>[],
            ),
          ),
        );
        history.seed(
          VisitEntry(
            ref: ref,
            city: 'Haifa',
            firstOpenedAt: DateTime.utc(2026),
            lastOpenedAt: DateTime.utc(2026),
            openCount: 1,
          ),
        );

        // Act
        await controller.load();

        // Assert
        expect(controller.lastVenueName, 'Cached Name');
        expect(
          controller.lastVenueHint,
          const VenueOpenHint(name: 'Cached Name', city: 'Haifa'),
        );
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

      test('load on a return to Explore keeps the query, results and chip, '
          'and searches nothing (issue #233)', () async {
        // Arrange: a search answered and a chip picked, as a user leaves
        // the tab with them.
        search.queueFound([_venue('sushi-bar', isOnline: true)]);
        controller.search('sushi', language: 'en', immediate: true);
        await pumpEventQueue();
        controller.toggleChip(DiscoveryChip.openNow);

        // Act: the screen's load on coming back.
        await controller.load();

        // Assert
        expect(controller.input, 'sushi');
        expect(controller.results.single.name, 'sushi-bar');
        expect(controller.activeChips, {DiscoveryChip.openNow});
        expect(search.byNameCalls, hasLength(1));
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
                  estimateClassifier: estimator,
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

      test('no chip is active by default and every result shows', () async {
        // Act
        await list([grill, sushi, cafe]);

        // Assert
        expect(controller.activeChips, isEmpty);
        expect(controller.visibleResults, [grill, sushi, cafe]);
      });

      test('open now keeps only venues the platform says are online', () async {
        // Arrange
        await list([grill, sushi, cafe]);

        // Act
        controller.toggleChip(DiscoveryChip.openNow);

        // Assert
        expect(controller.visibleResults, [grill]);
      });

      test('topCuisine is the most common tag and the cuisine chip keeps '
          'it', () async {
        // Arrange
        await list([grill, sushi, cafe]);

        // Act
        controller.toggleChip(DiscoveryChip.cuisine);

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

      test('tapping the active chip again clears it', () async {
        // Arrange
        await list([grill, sushi, cafe]);

        // Act: the same chip, twice.
        controller
          ..toggleChip(DiscoveryChip.openNow)
          ..toggleChip(DiscoveryChip.openNow);

        // Assert
        expect(controller.activeChips, isEmpty);
        expect(controller.visibleResults, hasLength(3));
      });

      test('chips combine: a venue must pass every active one', () async {
        // Arrange: grill is online and 8.0, sushi is offline and 8.0, cafe
        // is online with no numbers.
        final openCafe = _venue('open-cafe', tags: ['cafe'], isOnline: true);
        repository
          ..seedCache(_analysed(grill.ref, green: 8, yellow: 0, red: 2))
          ..seedCache(_analysed(sushi.ref, green: 8, yellow: 0, red: 2));
        await list([grill, sushi, openCafe]);

        // Act / Assert: each chip alone, then together.
        controller.toggleChip(DiscoveryChip.ketoEightPlus);
        expect(controller.visibleResults, [grill, sushi]);
        controller.toggleChip(DiscoveryChip.openNow);
        expect(controller.activeChips, {
          DiscoveryChip.ketoEightPlus,
          DiscoveryChip.openNow,
        });
        expect(controller.visibleResults, [grill]);
        controller.toggleChip(DiscoveryChip.cuisine);
        expect(controller.visibleResults, [grill]);

        // Act: drop one; the others still filter.
        controller.toggleChip(DiscoveryChip.ketoEightPlus);

        // Assert
        expect(controller.visibleResults, [grill]);
        controller.toggleChip(DiscoveryChip.openNow);
        expect(controller.visibleResults, [grill, sushi]);
      });

      test('the combination can match nothing', () async {
        // Arrange: the only high score is an offline venue.
        repository.seedCache(_analysed(sushi.ref, green: 8, yellow: 0, red: 2));
        await list([grill, sushi]);

        // Act
        controller
          ..toggleChip(DiscoveryChip.ketoEightPlus)
          ..toggleChip(DiscoveryChip.openNow);

        // Assert
        expect(controller.visibleResults, isEmpty);
      });

      test('activeChips is a read-only view', () async {
        // Act
        await list([grill]);

        // Assert
        expect(
          () => controller.activeChips.add(DiscoveryChip.openNow),
          throwsUnsupportedError,
        );
      });

      test('keto 8+ keeps scores of 8.0 and above only', () async {
        // Arrange: 8.0 exactly (8 green, 2 red), 7.5 (5 green, 5 yellow).
        repository
          ..seedCache(_analysed(grill.ref, green: 8, yellow: 0, red: 2))
          ..seedCache(_analysed(sushi.ref, green: 5, yellow: 5, red: 0));
        await list([grill, sushi, cafe]);

        // Act
        controller.toggleChip(DiscoveryChip.ketoEightPlus);

        // Assert
        expect(controller.cardNumbers(grill)?.score, 8.0);
        expect(controller.cardNumbers(sushi)?.score, 7.5);
        expect(controller.visibleResults, [grill]);
      });

      test('a new result set clears every chip', () async {
        // Arrange
        await list([grill, sushi]);
        controller
          ..toggleChip(DiscoveryChip.openNow)
          ..toggleChip(DiscoveryChip.cuisine);

        // Act
        await list([cafe]);

        // Assert
        expect(controller.activeChips, isEmpty);
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

      test('with the automatic quick score off, never fetch a menu or touch '
          'a classifier', () async {
        // Arrange: the controller holds the rule engine for the quick
        // score (issue #42, D21); with the automatic run off, nothing but
        // the explicit tap may reach it, and the repository is otherwise
        // only ever read.
        final classifier = estimator;
        repository.seedCache(_analysed(venue.ref, green: 3, yellow: 1, red: 1));
        search
          ..queueFound([venue, _venue('other')])
          ..queueFound([venue]);

        // Act: locate, search, filter, clear — everything the screen can
        // make the controller do.
        await controller.locate(language: 'en');
        controller
          ..toggleChip(DiscoveryChip.ketoEightPlus)
          ..toggleChip(DiscoveryChip.openNow)
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

    group('estimateVisible (issue #42, D13), the automatic run off', () {
      /// [count] venues named `v0`, `v1`, …, each scripted to load a menu
      /// with one dish, so the default [FakeMenuClassifier] answer places
      /// one green dish and scores it 10.0.
      List<Venue> venuesWithMenus(int count) {
        final venues = [for (var i = 0; i < count; i++) _venue('v$i')];
        for (final venue in venues) {
          repository.stub(venue.ref, _fetchedWithOneDish(venue.ref));
        }
        return venues;
      }

      Future<void> list(List<Venue> venues) async {
        search.queueFound(venues);
        await controller.locate(language: 'en');
      }

      test('fetches every visible venue without numbers, at most '
          'venueEstimateConcurrency at a time', () async {
        // Arrange: seven venues, one already scored from the cache.
        final venues = venuesWithMenus(7);
        repository.seedCache(
          _analysed(venues.first.ref, green: 1, yellow: 0, red: 0),
        );
        await list(venues);
        final gate = Completer<void>();
        repository.loadGate = gate.future;

        // Act
        final run = controller.estimateVisible();
        await pumpEventQueue();

        // Assert: only the bound is in flight, and progress says so.
        expect(repository.loadCalls, hasLength(venueEstimateConcurrency));
        expect(controller.isEstimating, isTrue);
        expect(controller.estimatedCount, 0);
        expect(controller.estimateTotal, 6);

        // Act
        gate.complete();
        await run;

        // Assert: all six loaded, never more than the bound at once, and
        // the cached one not fetched at all.
        expect(repository.maxConcurrentLoads, venueEstimateConcurrency);
        expect(
          repository.loadCalls.map((call) => call.ref),
          unorderedEquals(venues.skip(1).map((venue) => venue.ref)),
        );
        expect(controller.isEstimating, isFalse);
        expect(controller.estimatedCount, 0);
        expect(controller.estimateTotal, 0);
      });

      test('classifies with the injected rule engine only, saves the '
          'analysis and shows numbers marked as estimates', () async {
        // Arrange
        await settings.write(
          const AppSettings(netCarbLimitGrams: 10, seedOilFree: true),
        );
        final venues = venuesWithMenus(2);
        await list(venues);
        expect(controller.hasVisibleToEstimate, isTrue);

        // Act
        await controller.estimateVisible();

        // Assert: one rules classification per venue, under the user's
        // own verdict-shaping settings and with no AI consent passed on.
        expect(estimator.calls, hasLength(2));
        final options = estimator.calls.first.$2;
        expect(options.netCarbLimitGrams, 10);
        expect(options.seedOilFree, isTrue);
        expect(options.estimationConsentGiven, isFalse);
        expect(
          repository.savedAnalyses.map((saved) => saved.ref),
          unorderedEquals(venues.map((venue) => venue.ref)),
        );
        for (final venue in venues) {
          final numbers = controller.cardNumbers(venue);
          expect(numbers?.score, 10.0);
          expect(numbers?.green, 1);
          expect(numbers?.engine, isA<RulesEngine>());
        }
        expect(controller.hasAnyNumbers, isTrue);
        expect(controller.hasVisibleToEstimate, isFalse);
      });

      test('reports progress as each venue finishes', () async {
        // Arrange
        await list(venuesWithMenus(2));
        final progress = <(int, int)>[];
        controller.addListener(
          () => progress.add((
            controller.estimatedCount,
            controller.estimateTotal,
          )),
        );

        // Act
        await controller.estimateVisible();

        // Assert: started at 0 of 2, then 1 of 2, then done.
        expect(progress.first, (0, 2));
        expect(progress, contains((1, 2)));
        expect(progress.last, (0, 0));
      });

      test('one venue failing does not stop the others', () async {
        // Arrange: a fetch failure, and a menu the engine places nothing
        // in (the fake repository's default empty menu).
        final venues = venuesWithMenus(3);
        final broken = _venue('broken');
        final empty = _venue('empty');
        repository.stub(
          broken.ref,
          const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
        );
        await list([broken, ...venues, empty]);

        // Act
        await controller.estimateVisible();

        // Assert
        expect(repository.loadCalls, hasLength(5));
        for (final venue in venues) {
          expect(controller.cardNumbers(venue), isNotNull);
        }
        expect(controller.cardNumbers(broken), isNull);
        expect(controller.cardNumbers(empty), isNull);
        expect(controller.isEstimating, isFalse);
      });

      test('an analysis the engine could not produce is not saved', () async {
        // Arrange
        estimator.respondWith(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.noDishesFound,
          ),
        );
        final venue = venuesWithMenus(1).single;
        await list([venue]);

        // Act
        await controller.estimateVisible();

        // Assert
        expect(repository.savedAnalyses, isEmpty);
        expect(controller.cardNumbers(venue), isNull);
      });

      test('a new query cancels it: no further load, and late results are '
          'dropped', () async {
        // Arrange
        final venues = venuesWithMenus(6);
        await list(venues);
        final gate = Completer<void>();
        repository.loadGate = gate.future;
        final run = controller.estimateVisible();
        await pumpEventQueue();
        search.queueFound([_venue('sushi-bar')]);

        // Act
        controller.search('sushi', language: 'en', immediate: true);
        gate.complete();
        await run;
        await pumpEventQueue();

        // Assert
        expect(repository.loadCalls, hasLength(venueEstimateConcurrency));
        expect(estimator.calls, isEmpty);
        expect(repository.savedAnalyses, isEmpty);
        expect(controller.isEstimating, isFalse);
        expect(controller.results.single.name, 'sushi-bar');
        expect(controller.cardNumbers(venues.first), isNull);
      });

      test('a chip change cancels it too', () async {
        // Arrange
        await list(venuesWithMenus(6));
        final gate = Completer<void>();
        repository.loadGate = gate.future;
        final run = controller.estimateVisible();
        await pumpEventQueue();

        // Act
        controller.toggleChip(DiscoveryChip.openNow);
        gate.complete();
        await run;

        // Assert
        expect(repository.loadCalls, hasLength(venueEstimateConcurrency));
        expect(estimator.calls, isEmpty);
        expect(controller.isEstimating, isFalse);
      });

      test('a new location cancels it too', () async {
        // Arrange
        await list(venuesWithMenus(6));
        final gate = Completer<void>();
        repository.loadGate = gate.future;
        final run = controller.estimateVisible();
        await pumpEventQueue();

        // Act
        final located = controller.locate(language: 'en');
        gate.complete();
        await run;
        await located;

        // Assert
        expect(repository.loadCalls, hasLength(venueEstimateConcurrency));
        expect(estimator.calls, isEmpty);
      });

      test('a second tap while one runs starts nothing new', () async {
        // Arrange
        await list(venuesWithMenus(2));

        // Act
        final first = controller.estimateVisible();
        final second = controller.estimateVisible();
        await Future.wait([first, second]);

        // Assert
        expect(repository.loadCalls, hasLength(2));
      });

      test('does nothing with no list, or when every card has '
          'numbers', () async {
        // Act: no list yet.
        await controller.estimateVisible();

        // Assert
        expect(repository.loadCalls, isEmpty);
        expect(controller.hasVisibleToEstimate, isFalse);

        // Arrange: a list whose only venue is already scored.
        final venue = _venue('scored');
        repository.seedCache(_analysed(venue.ref, green: 2, yellow: 0, red: 0));
        await list([venue]);

        // Act
        await controller.estimateVisible();

        // Assert
        expect(repository.loadCalls, isEmpty);
        expect(controller.isEstimating, isFalse);
      });

      test('estimated numbers survive clearing a search back to the nearby '
          'list', () async {
        // Arrange
        final venue = venuesWithMenus(1).single;
        await list([venue]);
        await controller.estimateVisible();
        search.queueFound([_venue('other')]);
        controller.search('other', language: 'en', immediate: true);
        await pumpEventQueue();

        // Act
        controller.clearSearch();

        // Assert
        expect(controller.results.single, venue);
        expect(controller.cardNumbers(venue)?.engine, isA<RulesEngine>());
      });
    });

    group('automatic quick score (D21)', () {
      /// [count] venues named `v0`, `v1`, …, each scripted to load a
      /// one-dish menu the default [FakeMenuClassifier] answer scores
      /// 10.0, all taking orders so the *Open now* chip keeps them.
      List<Venue> venuesWithMenus(int count) {
        final venues = [
          for (var i = 0; i < count; i++) _venue('v$i', isOnline: true),
        ];
        for (final venue in venues) {
          repository.stub(venue.ref, _fetchedWithOneDish(venue.ref));
        }
        return venues;
      }

      /// Lets a run started by the controller itself finish.
      Future<void> settle() async {
        while (controller.isEstimating) {
          await pumpEventQueue();
        }
      }

      setUp(() {
        controller.dispose();
        controller = build(autoEstimateLimit: 4);
      });

      test('scores the first autoEstimateLimit venues on its own when a '
          'list arrives, at most venueEstimateConcurrency at a time', () async {
        // Arrange: seven venues, none scored.
        final venues = venuesWithMenus(7);
        search.queueFound(venues);
        final gate = Completer<void>();
        repository.loadGate = gate.future;

        // Act: the list lands; nothing is tapped.
        await controller.locate(language: 'en');
        await pumpEventQueue();

        // Assert: a run is going, bounded, over the cap's worth of venues.
        expect(controller.isEstimating, isTrue);
        expect(controller.estimateTotal, 4);
        expect(repository.loadCalls, hasLength(venueEstimateConcurrency));

        // Act
        gate.complete();
        await settle();

        // Assert: the first four, in list order, scored and marked as
        // estimates; the rest untouched and still on offer.
        expect(repository.maxConcurrentLoads, venueEstimateConcurrency);
        expect(
          repository.loadCalls.map((call) => call.ref),
          venues.take(4).map((venue) => venue.ref),
        );
        expect(estimator.calls, hasLength(4));
        for (final venue in venues.take(4)) {
          expect(controller.cardNumbers(venue)?.score, 10.0);
          expect(controller.cardNumbers(venue)?.engine, isA<RulesEngine>());
        }
        for (final venue in venues.skip(4)) {
          expect(controller.cardNumbers(venue), isNull);
        }
        expect(controller.hasVisibleToEstimate, isTrue);
      });

      test(
        '"Quick score the rest" then covers the venues past the cap',
        () async {
          // Arrange
          final venues = venuesWithMenus(7);
          search.queueFound(venues);
          await controller.locate(language: 'en');
          await settle();

          // Act
          await controller.estimateVisible();

          // Assert
          expect(
            repository.loadCalls.map((call) => call.ref),
            venues.map((venue) => venue.ref),
          );
          for (final venue in venues) {
            expect(controller.cardNumbers(venue), isNotNull);
          }
          expect(controller.hasVisibleToEstimate, isFalse);
        },
      );

      test('a by-name result list starts it too', () async {
        // Arrange
        final venues = venuesWithMenus(2);
        search.queueFound(venues);

        // Act
        controller.search('v', language: 'en', immediate: true);
        await pumpEventQueue();
        await settle();

        // Assert
        expect(repository.loadCalls, hasLength(2));
        expect(controller.cardNumbers(venues.last)?.score, 10.0);
      });

      test('a venue already scored from the cache is not fetched', () async {
        // Arrange
        final venues = venuesWithMenus(3);
        repository.seedCache(
          _analysed(venues[1].ref, green: 1, yellow: 0, red: 0),
        );
        search.queueFound(venues);

        // Act
        await controller.locate(language: 'en');
        await settle();

        // Assert
        expect(repository.loadCalls.map((call) => call.ref), [
          venues[0].ref,
          venues[2].ref,
        ]);
      });

      test('a chip change scores only venues no run has fetched yet, and '
          'a second toggle fetches nothing', () async {
        // Arrange: six venues, the first four scored on arrival.
        final venues = venuesWithMenus(6);
        search.queueFound(venues);
        await controller.locate(language: 'en');
        await settle();
        expect(repository.loadCalls, hasLength(4));

        // Act: every venue is taking orders, so the chip shows all six.
        controller.toggleChip(DiscoveryChip.openNow);
        await settle();

        // Assert: only the two the first run never reached.
        expect(repository.loadCalls.skip(4).map((call) => call.ref), [
          venues[4].ref,
          venues[5].ref,
        ]);

        // Act
        controller.toggleChip(DiscoveryChip.openNow);
        await settle();
        controller.toggleChip(DiscoveryChip.openNow);
        await settle();

        // Assert
        expect(repository.loadCalls, hasLength(6));
        expect(controller.hasVisibleToEstimate, isFalse);
      });

      test('a venue whose menu could not be read is not fetched again until '
          'a new list arrives', () async {
        // Arrange
        final broken = _venue('broken', isOnline: true);
        repository.stub(
          broken.ref,
          const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
        );
        final venues = [broken, ...venuesWithMenus(2)];
        search.queueFound(venues);
        await controller.locate(language: 'en');
        await settle();
        expect(repository.loadCalls, hasLength(3));
        expect(controller.cardNumbers(broken), isNull);

        // Act: a chip change starts a run with nothing left to fetch.
        controller.toggleChip(DiscoveryChip.openNow);
        await settle();

        // Assert: no card is on offer either, so no tap can repeat it.
        expect(repository.loadCalls, hasLength(3));
        expect(controller.hasVisibleToEstimate, isFalse);

        // Act: a fresh list is a fresh start.
        search.queueFound(venues);
        await controller.locate(language: 'en');
        await settle();

        // Assert
        expect(repository.loadCalls, hasLength(6));
      });

      test('clearing a search back to the nearby list fetches nothing: it '
          'was scored when it arrived', () async {
        // Arrange
        final nearby = venuesWithMenus(1).single;
        search.queueFound([nearby]);
        await controller.locate(language: 'en');
        await settle();
        final other = _venue('other');
        repository.stub(other.ref, _fetchedWithOneDish(other.ref));
        search.queueFound([other]);
        controller.search('other', language: 'en', immediate: true);
        await pumpEventQueue();
        await settle();
        expect(repository.loadCalls, hasLength(2));

        // Act
        controller.clearSearch();
        await pumpEventQueue();

        // Assert
        expect(repository.loadCalls, hasLength(2));
        expect(controller.results.single, nearby);
        expect(controller.cardNumbers(nearby)?.engine, isA<RulesEngine>());
        expect(controller.hasVisibleToEstimate, isFalse);
      });

      test('a new query cancels a run in flight, and its venues are not '
          'refetched by the next automatic run of the same list', () async {
        // Arrange
        final venues = venuesWithMenus(4);
        search.queueFound(venues);
        final gate = Completer<void>();
        repository.loadGate = gate.future;
        await controller.locate(language: 'en');
        await pumpEventQueue();
        expect(repository.loadCalls, hasLength(venueEstimateConcurrency));
        search.queueFound([_venue('sushi-bar')]);

        // Act
        controller.search('sushi', language: 'en', immediate: true);
        gate.complete();
        await pumpEventQueue();
        await settle();

        // Assert: the three in flight were dropped, the fourth never
        // started, and the new list's one venue was fetched instead.
        expect(estimator.calls.map((call) => call.$1.venueRef), [
          const VenueRef(source: MenuSource.wolt, platformId: 'sushi-bar'),
        ]);
        expect(repository.loadCalls, hasLength(venueEstimateConcurrency + 1));
        expect(controller.cardNumbers(venues.first), isNull);
      });

      test('card numbers count food only: a drinks category is listed but '
          'never scored (D21)', () async {
        // Arrange: a steak and a cola; the fake engine marks both green.
        final venue = _venue('bar', isOnline: true);
        repository.stub(
          venue.ref,
          MenuFetched(
            menu: Menu(
              venueRef: venue.ref,
              currency: 'ILS',
              fetchedAt: DateTime.utc(2026),
              categories: const <MenuCategory>[
                MenuCategory(
                  id: 'mains',
                  name: 'Mains',
                  dishes: <Dish>[
                    Dish(
                      id: 'steak',
                      name: 'Steak',
                      description: '',
                      price: 80,
                      options: <DishOption>[],
                    ),
                  ],
                ),
                MenuCategory(
                  id: 'drinks',
                  name: 'שתייה',
                  dishes: <Dish>[
                    Dish(
                      id: 'cola',
                      name: 'קולה',
                      description: '',
                      price: 12,
                      options: <DishOption>[],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        search.queueFound([venue]);

        // Act
        await controller.locate(language: 'en');
        await settle();

        // Assert
        final numbers = controller.cardNumbers(venue);
        expect(numbers?.score, 10.0);
        expect(numbers?.green, 1);
        expect(numbers?.yellow, 0);
      });

      test('a limit of 0 turns the automatic run off', () async {
        // Arrange
        controller.dispose();
        controller = build();
        final venues = venuesWithMenus(2);
        search.queueFound(venues);

        // Act
        await controller.locate(language: 'en');
        await pumpEventQueue();

        // Assert
        expect(repository.loadCalls, isEmpty);
        expect(controller.hasVisibleToEstimate, isTrue);
      });
    });

    group('choosePlace (issue #443)', () {
      final telAviv = knownPlaceById('tel-aviv')!;
      final haifa = knownPlaceById('haifa')!;

      test('lists the venues around the place in the given language, with '
          'no call to the location service', () async {
        // Arrange
        search.queueFound([_venue('a'), _venue('b')]);

        // Act
        await controller.choosePlace(haifa, language: 'he');

        // Assert
        final call = search.nearbyCalls.single;
        expect(call.latitude, haifa.latitude);
        expect(call.longitude, haifa.longitude);
        expect(call.language, 'he');
        expect(location.currentCallCount, 0);
        expect(controller.chosenPlace, haifa);
        expect(controller.position?.latitude, haifa.latitude);
        expect(controller.position?.longitude, haifa.longitude);
        expect(controller.results.map((v) => v.name), ['a', 'b']);
        expect(controller.hasSearched, isTrue);
        expect(controller.phase, DiscoveryPhase.idle);
      });

      test('passes through searching, never locating', () async {
        // Arrange
        final phases = <DiscoveryPhase>[];
        controller.addListener(() => phases.add(controller.phase));

        // Act
        await controller.choosePlace(haifa, language: 'en');

        // Assert
        expect(phases, isNot(contains(DiscoveryPhase.locating)));
        expect(phases.first, DiscoveryPhase.searching);
        expect(phases.last, DiscoveryPhase.idle);
      });

      test('saves the place, leaving every other setting as it was', () async {
        // Arrange
        await settings.write(
          const AppSettings(languageTag: 'he', netCarbLimitGrams: 9),
        );

        // Act
        await controller.choosePlace(haifa, language: 'en');

        // Assert
        expect(
          await settings.read(),
          const AppSettings(
            languageTag: 'he',
            netCarbLimitGrams: 9,
            discoveryPlaceId: 'haifa',
          ),
        );
      });

      test('choosing the place already saved writes nothing', () async {
        // Arrange
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));
        final writesBefore = settings.writeCallCount;

        // Act
        await controller.choosePlace(haifa, language: 'en');

        // Assert
        expect(settings.writeCallCount, writesBefore);
      });

      test('measures card distances from the place', () async {
        // Arrange
        await controller.choosePlace(telAviv, language: 'en');

        // Act
        final km = controller.distanceKmTo(
          _venue('a', latitude: telAviv.latitude, longitude: telAviv.longitude),
        );

        // Assert
        expect(km, closeTo(0, 0.001));
      });

      test('a search by name is then ranked around the place', () async {
        // Arrange
        await controller.choosePlace(haifa, language: 'en');

        // Act
        controller.search('sushi', language: 'en', immediate: true);
        await pumpEventQueue();

        // Assert
        final call = search.byNameCalls.single;
        expect(call.latitude, haifa.latitude);
        expect(call.longitude, haifa.longitude);
      });

      test("clearing a search puts the place's list back without a new "
          'request', () async {
        // Arrange
        search.queueFound([_venue('near-haifa')]);
        await controller.choosePlace(haifa, language: 'en');
        search.queueFound([_venue('by-name')]);
        controller.search('sushi', language: 'en', immediate: true);
        await pumpEventQueue();

        // Act
        controller.clearSearch();

        // Assert
        expect(controller.results.map((v) => v.name), ['near-haifa']);
        expect(search.nearbyCalls, hasLength(1));
      });

      test('a failed search keeps the place, and retry asks around it '
          'again', () async {
        // Arrange
        search
          ..queueFailed(VenueSearchFailureReason.offline)
          ..queueFound([_venue('a')]);

        // Act
        await controller.choosePlace(haifa, language: 'en');

        // Assert
        expect(controller.failure, VenueSearchFailureReason.offline);
        expect(controller.chosenPlace, haifa);
        expect(controller.position?.latitude, haifa.latitude);

        // Act
        await controller.retry();

        // Assert
        expect(controller.failure, isNull);
        expect(search.nearbyCalls, hasLength(2));
        expect(search.nearbyCalls.last.latitude, haifa.latitude);
        expect(controller.results.map((v) => v.name), ['a']);
      });

      test('clears a denial the user has just worked around', () async {
        // Arrange
        location.result = const LocationDenied(permanently: true);
        await controller.locate(language: 'en');
        expect(controller.locationOutcome, isA<LocationDenied>());

        // Act
        await controller.choosePlace(haifa, language: 'en');

        // Assert
        expect(controller.locationOutcome, isNull);
      });

      test('choosing another place replaces the first', () async {
        // Arrange
        await controller.choosePlace(haifa, language: 'en');

        // Act
        await controller.choosePlace(telAviv, language: 'en');

        // Assert
        expect(controller.chosenPlace, telAviv);
        expect(search.nearbyCalls.last.latitude, telAviv.latitude);
        expect((await settings.read()).discoveryPlaceId, 'tel-aviv');
      });

      test('a later choice wins over an earlier one still in flight', () async {
        // Arrange: the first search hangs.
        final gate = Completer<void>();
        search
          ..gate = gate.future
          ..queueFound([_venue('haifa-venue')])
          ..queueFound([_venue('tel-aviv-venue')]);
        final first = controller.choosePlace(haifa, language: 'en');
        final second = controller.choosePlace(telAviv, language: 'en');

        // Act
        gate.complete();
        await Future.wait([first, second]);

        // Assert: only the second answer is shown.
        expect(controller.chosenPlace, telAviv);
        expect(controller.results.map((v) => v.name), ['tel-aviv-venue']);
      });

      test('a found device position replaces the place and clears the '
          'saved one', () async {
        // Arrange
        await controller.choosePlace(haifa, language: 'en');

        // Act
        final result = await controller.locate(language: 'en');

        // Assert
        expect(result, isA<LocationFound>());
        expect(controller.chosenPlace, isNull);
        expect(controller.position?.latitude, 32.0809);
        expect((await settings.read()).discoveryPlaceId, isNull);
      });

      test('a found device position clears a place saved by an earlier '
          'launch that was never restored', () async {
        // Arrange: saved, but load has not run.
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect((await settings.read()).discoveryPlaceId, isNull);
      });

      test('a found device position with no place saved writes '
          'nothing', () async {
        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(settings.writeCallCount, 0);
      });

      test('a refused or failed device position leaves the place, its '
          'position, its list and the saved choice alone', () async {
        for (final refusal in const <LocationResult>[
          LocationDenied(permanently: false),
          LocationUnavailable(reason: LocationUnavailableReason.timeout),
        ]) {
          // Arrange
          search.queueFound([_venue('near-haifa')]);
          await controller.choosePlace(haifa, language: 'en');
          location.result = refusal;

          // Act
          final result = await controller.locate(language: 'en');

          // Assert
          expect(result, refusal);
          expect(controller.locationOutcome, refusal);
          expect(controller.chosenPlace, haifa);
          expect(controller.position?.latitude, haifa.latitude);
          expect(controller.results.map((v) => v.name), ['near-haifa']);
          expect((await settings.read()).discoveryPlaceId, 'haifa');
        }
      });

      test('locate completes with null when a newer search superseded '
          'it', () async {
        // Arrange: the device takes its time.
        final gate = Completer<void>();
        location.gate = gate.future;
        final locating = controller.locate(language: 'en');

        // Act: the user picks a place meanwhile.
        await controller.choosePlace(haifa, language: 'en');
        gate.complete();

        // Assert: the late position changes nothing.
        expect(await locating, isNull);
        expect(controller.chosenPlace, haifa);
        expect(controller.locationOutcome, isNull);
      });
    });

    group('load restores the chosen place (issue #443)', () {
      final haifa = knownPlaceById('haifa')!;

      test('makes the saved place the chosen one and lists the venues '
          'around it when given a language', () async {
        // Arrange
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));
        search.queueFound([_venue('near-haifa')]);

        // Act
        await controller.load(language: 'he');

        // Assert
        expect(controller.chosenPlace, haifa);
        expect(controller.position?.latitude, haifa.latitude);
        final call = search.nearbyCalls.single;
        expect(call.latitude, haifa.latitude);
        expect(call.longitude, haifa.longitude);
        expect(call.language, 'he');
        expect(controller.results.map((v) => v.name), ['near-haifa']);
        expect(location.currentCallCount, 0);
      });

      test('without a language it restores the place and searches '
          'nothing', () async {
        // Arrange
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));

        // Act
        await controller.load();

        // Assert
        expect(controller.chosenPlace, haifa);
        expect(controller.position?.longitude, haifa.longitude);
        expect(search.nearbyCalls, isEmpty);
        expect(controller.hasSearched, isFalse);
      });

      test('with nothing saved it restores nothing and searches '
          'nothing', () async {
        // Act
        await controller.load(language: 'en');

        // Assert
        expect(controller.chosenPlace, isNull);
        expect(controller.position, isNull);
        expect(search.nearbyCalls, isEmpty);
      });

      test('an id the list no longer holds is ignored', () async {
        // Arrange
        await settings.write(const AppSettings(discoveryPlaceId: 'atlantis'));

        // Act
        await controller.load(language: 'en');

        // Assert
        expect(controller.chosenPlace, isNull);
        expect(controller.position, isNull);
        expect(search.nearbyCalls, isEmpty);
      });

      test('only the first load restores: a return to Explore searches '
          'nothing more', () async {
        // Arrange
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));
        await controller.load(language: 'en');

        // Act
        await controller.load(language: 'en');
        await controller.load(language: 'en');

        // Assert
        expect(search.nearbyCalls, hasLength(1));
      });

      test('a place saved after the first load is not picked up by a later '
          'one', () async {
        // Arrange: the first load found nothing saved.
        await controller.load(language: 'en');
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));

        // Act
        await controller.load(language: 'en');

        // Assert
        expect(controller.chosenPlace, isNull);
        expect(search.nearbyCalls, isEmpty);
      });

      test('a position the device already gave is not replaced', () async {
        // Arrange: located before the first load answers. The locate
        // itself clears the saved place, so save it again afterwards.
        await controller.locate(language: 'en');
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));

        // Act
        await controller.load(language: 'en');

        // Assert
        expect(controller.chosenPlace, isNull);
        expect(controller.position?.latitude, 32.0809);
        expect(search.nearbyCalls, hasLength(1));
      });

      test('restores the place but does not search over a query already '
          'typed', () async {
        // Arrange
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));
        controller.setInput('sushi');

        // Act
        await controller.load(language: 'en');

        // Assert
        expect(controller.chosenPlace, haifa);
        expect(search.nearbyCalls, isEmpty);
        expect(controller.input, 'sushi');
      });

      test('a restored search that fails can be retried', () async {
        // Arrange
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));
        search
          ..queueFailed(VenueSearchFailureReason.offline)
          ..queueFound([_venue('near-haifa')]);
        await controller.load(language: 'en');
        expect(controller.failure, VenueSearchFailureReason.offline);

        // Act
        await controller.retry();

        // Assert
        expect(controller.failure, isNull);
        expect(controller.results.map((v) => v.name), ['near-haifa']);
      });
    });

    group('streets (issue #449)', () {
      const herzl = StreetPlace(
        label: 'הרצל 10, תל אביב',
        city: 'תל אביב',
        latitude: 32.0625697,
        longitude: 34.7698648,
      );
      final haifa = knownPlaceById('haifa')!;
      late FakePlaceSearchService places;

      setUp(() {
        places = FakePlaceSearchService();
        controller.dispose();
        controller = VenueSearchController(
          settings,
          repository,
          locationService: location,
          venueSearchService: search,
          estimateClassifier: estimator,
          autoEstimateLimit: 0,
          visitHistory: history,
          placeSearchService: places,
        );
      });

      test('searchStreets asks the place search once, in the given language, '
          'and changes nothing here', () async {
        // Arrange
        places.queueFound(const <StreetPlace>[herzl]);

        // Act
        final result = await controller.searchStreets(
          'הרצל 10',
          language: 'he',
        );

        // Assert
        expect(controller.canSearchStreets, isTrue);
        expect(result, const PlacesFound(<StreetPlace>[herzl]));
        expect(places.calls, <PlaceSearchCall>[
          (query: 'הרצל 10', language: 'he'),
        ]);
        expect(controller.chosenStreet, isNull);
        expect(controller.position, isNull);
        expect(search.nearbyCalls, isEmpty);
        expect(await settings.read(), const AppSettings());
      });

      test('without a place search there is no street search, and asking '
          'sends nothing', () async {
        // Arrange
        final plain = build();
        addTearDown(plain.dispose);

        // Act
        final result = await plain.searchStreets('herzl', language: 'en');

        // Assert
        expect(plain.canSearchStreets, isFalse);
        expect(
          result,
          const PlaceSearchFailed(PlaceSearchFailureReason.backendUnreachable),
        );
        expect(places.calls, isEmpty);
      });

      test('chooseStreet lists the venues around the street, measures from '
          'it and saves it in place of any city', () async {
        // Arrange
        await settings.write(const AppSettings(discoveryPlaceId: 'haifa'));
        search.queueFound([
          _venue('a', latitude: 32.0625697, longitude: 34.7698648),
        ]);

        // Act
        await controller.chooseStreet(herzl, language: 'he');

        // Assert
        final call = search.nearbyCalls.single;
        expect(call.latitude, herzl.latitude);
        expect(call.longitude, herzl.longitude);
        expect(call.language, 'he');
        expect(location.currentCallCount, 0);
        expect(controller.chosenStreet, herzl);
        expect(controller.chosenPlace, isNull);
        expect(controller.position?.latitude, herzl.latitude);
        expect(
          controller.distanceKmTo(controller.results.single),
          closeTo(0, 0.001),
        );
        final saved = await settings.read();
        expect(saved.discoveryStreet, herzl);
        expect(saved.discoveryPlaceId, isNull);
      });

      test('the distance filter measures from the chosen street', () async {
        // Arrange
        search.queueFound([
          _venue('near', latitude: 32.063, longitude: 34.770),
          _venue('far', latitude: 32.794, longitude: 34.990),
        ]);
        await controller.chooseStreet(herzl, language: 'en');

        // Act
        controller.setRadius(1);

        // Assert
        expect(controller.visibleResults.map((v) => v.name), ['near']);
      });

      test(
        'choosing a city replaces the street, with no place search',
        () async {
          // Arrange
          await controller.chooseStreet(herzl, language: 'en');

          // Act
          await controller.choosePlace(haifa, language: 'en');

          // Assert
          expect(controller.chosenPlace, haifa);
          expect(controller.chosenStreet, isNull);
          expect(places.calls, isEmpty);
          final saved = await settings.read();
          expect(saved.discoveryPlaceId, 'haifa');
          expect(saved.discoveryStreet, isNull);
        },
      );

      test('a found device position replaces the street and clears the '
          'saved one', () async {
        // Arrange
        await controller.chooseStreet(herzl, language: 'en');

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(controller.chosenStreet, isNull);
        expect(controller.position?.latitude, 32.0809);
        expect((await settings.read()).discoveryStreet, isNull);
      });

      test('a refused device position keeps the street', () async {
        // Arrange
        await controller.chooseStreet(herzl, language: 'en');
        location.result = const LocationDenied(permanently: false);

        // Act
        await controller.locate(language: 'en');

        // Assert
        expect(controller.chosenStreet, herzl);
        expect((await settings.read()).discoveryStreet, herzl);
      });

      test('a failed nearby search keeps the street, and retry asks around '
          'it again', () async {
        // Arrange
        search
          ..queueFailed(VenueSearchFailureReason.offline)
          ..queueFound([_venue('a')]);
        await controller.chooseStreet(herzl, language: 'en');

        // Act
        await controller.retry();

        // Assert
        expect(controller.chosenStreet, herzl);
        expect(search.nearbyCalls, hasLength(2));
        expect(search.nearbyCalls.last.latitude, herzl.latitude);
        expect(controller.results.map((v) => v.name), ['a']);
      });

      test('the first load restores a saved street and lists around it, '
          'with no place search', () async {
        // Arrange
        await settings.write(
          const AppSettings(
            discoveryStreet: StreetPlace(
              label: 'הרצל 10, תל אביב',
              latitude: 32.0625697,
              longitude: 34.7698648,
            ),
          ),
        );
        search.queueFound([_venue('near-herzl')]);

        // Act
        await controller.load(language: 'he');

        // Assert
        expect(controller.chosenStreet?.label, 'הרצל 10, תל אביב');
        expect(controller.chosenPlace, isNull);
        expect(controller.position?.longitude, 34.7698648);
        expect(search.nearbyCalls.single.latitude, 32.0625697);
        expect(controller.results.map((v) => v.name), ['near-herzl']);
        expect(places.calls, isEmpty);
      });

      test('a later load does not restore the street again', () async {
        // Arrange
        await controller.load();
        await settings.write(const AppSettings(discoveryStreet: herzl));

        // Act
        await controller.load(language: 'en');

        // Assert
        expect(controller.chosenStreet, isNull);
        expect(search.nearbyCalls, isEmpty);
      });

      test('a saved city wins over a saved street the list no longer '
          'reaches, and a city id the list lacks falls back to the '
          'street', () async {
        // Arrange: a record that somehow holds an unknown id and a street.
        await settings.write(
          const AppSettings(
            discoveryPlaceId: 'atlantis',
            discoveryStreet: herzl,
          ),
        );

        // Act
        await controller.load();

        // Assert
        expect(controller.chosenPlace, isNull);
        expect(controller.chosenStreet, herzl);
      });
    });

    group('distance filter (issue #443)', () {
      final telAviv = knownPlaceById('tel-aviv')!;

      /// A venue [km] kilometres due north of Tel Aviv's centre.
      Venue at(String slug, double km, {bool? isOnline}) => _venue(
        slug,
        isOnline: isOnline,
        // One degree of latitude is about 111.2 km.
        latitude: telAviv.latitude + km / 111.2,
        longitude: telAviv.longitude,
      );

      late Venue near;
      late Venue walk;
      late Venue drive;
      late Venue far;
      late Venue unplaced;

      setUp(() {
        near = at('near', 0.5, isOnline: true);
        walk = at('walk', 1.5, isOnline: false);
        drive = at('drive', 4, isOnline: true);
        far = at('far', 20, isOnline: true);
        unplaced = _venue('unplaced', isOnline: true);
      });

      Future<void> list() async {
        search.queueFound([near, walk, drive, far, unplaced]);
        await controller.choosePlace(telAviv, language: 'en');
      }

      test('is "any distance" by default, and every result shows', () async {
        // Act
        await list();

        // Assert
        expect(controller.radiusKm, isNull);
        expect(controller.visibleResults, [near, walk, drive, far, unplaced]);
      });

      test('keeps only venues within the radius, in the same order', () async {
        // Arrange
        await list();

        // Act and assert: each offered distance.
        controller.setRadius(1);
        expect(controller.visibleResults, [near]);
        controller.setRadius(2);
        expect(controller.visibleResults, [near, walk]);
        controller.setRadius(5);
        expect(controller.visibleResults, [near, walk, drive]);
        controller.setRadius(10);
        expect(controller.visibleResults, [near, walk, drive]);
      });

      test('hides a venue with no coordinates while a radius is set', () async {
        // Arrange
        await list();

        // Act
        controller.setRadius(10);

        // Assert
        expect(controller.visibleResults, isNot(contains(unplaced)));
      });

      test('null puts every result back', () async {
        // Arrange
        await list();
        controller.setRadius(1);
        expect(controller.visibleResults, [near]);

        // Act
        controller.setRadius(null);

        // Assert
        expect(controller.radiusKm, isNull);
        expect(controller.visibleResults, [near, walk, drive, far, unplaced]);
      });

      test('combines with the chips: a venue must pass both', () async {
        // Arrange
        await list();

        // Act
        controller
          ..setRadius(2)
          ..toggleChip(DiscoveryChip.openNow);

        // Assert: walk is within 2 km but closed.
        expect(controller.visibleResults, [near]);
      });

      test('can match nothing', () async {
        // Arrange
        search.queueFound([far]);
        await controller.choosePlace(telAviv, language: 'en');

        // Act
        controller.setRadius(1);

        // Assert
        expect(controller.results, [far]);
        expect(controller.visibleResults, isEmpty);
      });

      test('notifies once per change and not at all when unchanged', () async {
        // Arrange
        await list();
        var notifyCount = 0;

        // Act: listen, then two changes with a repeat in between.
        controller
          ..addListener(() => notifyCount++)
          ..setRadius(2)
          ..setRadius(2)
          ..setRadius(5);

        // Assert
        expect(notifyCount, 2);
      });

      test('stays through a new result list, where the chips are '
          'cleared', () async {
        // Arrange
        await list();
        controller
          ..setRadius(2)
          ..toggleChip(DiscoveryChip.openNow);

        // Act: a search by name answers.
        search.queueFound([near, far]);
        controller.search('sushi', language: 'en', immediate: true);
        await pumpEventQueue();

        // Assert
        expect(controller.activeChips, isEmpty);
        expect(controller.radiusKm, 2);
        expect(controller.visibleResults, [near]);
      });

      test('stays when a cleared search puts the nearby list back', () async {
        // Arrange
        await list();
        controller.setRadius(2);
        search.queueFound([far]);
        controller.search('sushi', language: 'en', immediate: true);
        await pumpEventQueue();

        // Act
        controller.clearSearch();

        // Assert
        expect(controller.radiusKm, 2);
        expect(controller.visibleResults, [near, walk]);
      });

      test('measures from the device position as it does from a chosen '
          'place', () async {
        // Arrange: the fake device sits at 32.0809, 34.7806.
        final here = _venue('here', latitude: 32.0809, longitude: 34.7806);
        final away = _venue('away', latitude: 32.5, longitude: 34.7806);
        search.queueFound([here, away]);
        await controller.locate(language: 'en');

        // Act
        controller.setRadius(5);

        // Assert
        expect(controller.visibleResults, [here]);
      });

      test('filters nothing while there is no position to measure '
          'from', () async {
        // Arrange: a search by name before any position.
        search.queueFound([near, unplaced]);
        controller.search('sushi', language: 'en', immediate: true);
        await pumpEventQueue();

        // Act
        controller.setRadius(1);

        // Assert
        expect(controller.position, isNull);
        expect(controller.visibleResults, [near, unplaced]);
      });

      test('cancels a running quick score, as a chip change does', () async {
        // Arrange: a tapped quick score hangs on its first menus.
        for (final venue in [near, walk, drive, far]) {
          repository.stub(venue.ref, _fetchedWithOneDish(venue.ref));
        }
        await list();
        final gate = Completer<void>();
        repository.loadGate = gate.future;
        final run = controller.estimateVisible();
        await pumpEventQueue();
        expect(controller.isEstimating, isTrue);

        // Act
        controller.setRadius(1);
        gate.complete();
        await run;

        // Assert: the run stopped and its late answers were dropped.
        expect(controller.isEstimating, isFalse);
        expect(controller.cardNumbers(near), isNull);
      });

      test('the automatic quick score then covers what is in view, '
          'fetching no venue twice (D21)', () async {
        // Arrange: the automatic run covers the first two of the list.
        controller.dispose();
        controller = build(autoEstimateLimit: 2);
        for (final venue in [near, walk, drive, far]) {
          repository.stub(venue.ref, _fetchedWithOneDish(venue.ref));
        }
        await list();
        while (controller.isEstimating) {
          await pumpEventQueue();
        }
        expect(repository.loadCalls.map((c) => c.ref), [near.ref, walk.ref]);

        // Act: widen to 5 km, which brings `drive` into the first cards
        // without numbers.
        controller.setRadius(5);
        while (controller.isEstimating) {
          await pumpEventQueue();
        }

        // Assert: only the venue no run had fetched was fetched.
        expect(repository.loadCalls.map((c) => c.ref), [
          near.ref,
          walk.ref,
          drive.ref,
        ]);
        expect(controller.cardNumbers(drive)?.score, 10.0);
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
