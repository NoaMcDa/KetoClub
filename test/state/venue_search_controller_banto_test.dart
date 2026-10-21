import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_venue_search_service.dart';

/// A dish priced 50 with [options].
Dish _dish(
  String id,
  String name,
  String description, {
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 50,
  options: options,
);

/// A Wolt venue addressed by [slug].
Venue _venue(String slug) => Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: slug),
  name: slug,
);

/// One main in each state for a sesame allergy, and a drink that counts
/// for nothing (D21); the omelette is the one a lactose intolerance
/// avoids.
Menu _grillMenu(VenueRef ref) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'mains',
      name: 'Mains',
      dishes: <Dish>[
        _dish('salmon', 'Grilled salmon', 'With a green salad'),
        _dish(
          'chicken',
          'Chicken skewers',
          'With a choice of sauce',
          options: const <DishOption>[
            DishOption(
              name: 'Sauce',
              values: <String>['Tahini', 'Cream sauce'],
            ),
          ],
        ),
        _dish('falafel', 'Falafel plate', 'With chopped salad'),
        _dish('steak', 'Steak', 'Sesame crusted'),
        _dish('omelette', 'Cheese omelette', 'Three eggs and cheddar'),
      ],
    ),
    MenuCategory(
      id: 'drinks',
      name: 'Drinks',
      dishes: <Dish>[_dish('lemonade', 'Lemonade', '')],
    ),
  ],
);

/// A menu whose every main a sesame allergy avoids.
Menu _sesameHouseMenu(VenueRef ref) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'mains',
      name: 'Mains',
      dishes: <Dish>[
        _dish('steak', 'Steak', 'Sesame crusted'),
        _dish('tuna', 'Seared tuna', 'Rolled in sesame seeds'),
      ],
    ),
  ],
);

/// The rule engine the quick score classifies with, at a fixed time.
final HeuristicMenuClassifier _rules = HeuristicMenuClassifier(
  clock: FakeClock(DateTime.utc(2026)),
);

/// [menu] with the rule engine's keto-only analysis, as the quick score
/// caches it (D21).
Future<CachedMenu> _cachedRules(Menu menu) async =>
    CachedMenu(menu: menu, analysis: await _rules.classify(menu));

/// A profile holding [ids].
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

/// Settings whose own profile holds [ids].
AppSettings _settingsWith(List<RestrictionId> ids) =>
    AppSettings(profile: _profile(ids));

void main() {
  group('VenueSearchController, Banto fit (issue #410)', () {
    late FakeSettingsStore settings;
    late FakeMenuRepository repository;
    late FakeLocationService location;
    late FakeVenueSearchService search;
    late VenueSearchController controller;

    final grill = _venue('grill');
    final sesameHouse = _venue('sesame-house');
    final unscored = _venue('unscored');

    /// A controller over the rule engine, with the automatic run off
    /// unless [autoEstimateLimit] says otherwise.
    VenueSearchController build({int autoEstimateLimit = 0}) =>
        VenueSearchController(
          settings,
          repository,
          locationService: location,
          venueSearchService: search,
          estimateClassifier: _rules,
          autoEstimateLimit: autoEstimateLimit,
        );

    /// Caches the grill and the sesame house with the rules' analysis and
    /// lists them with [unscored], nearby.
    Future<void> listThree() async {
      repository
        ..seedCache(await _cachedRules(_grillMenu(grill.ref)))
        ..seedCache(await _cachedRules(_sesameHouseMenu(sesameHouse.ref)));
      search.queueFound(<Venue>[grill, sesameHouse, unscored]);
      await controller.locate(language: 'en');
    }

    setUp(() {
      settings = FakeSettingsStore(
        initial: _settingsWith(<RestrictionId>[RestrictionId.sesame]),
      );
      repository = FakeMenuRepository();
      location = FakeLocationService();
      search = FakeVenueSearchService();
      controller = build();
    });

    tearDown(() => controller.dispose());

    test(
      'a cached card counts its food dishes by state for the profile',
      () async {
        // Arrange
        await listThree();

        // Act
        await controller.load(bantoMode: true);

        // Assert
        expect(controller.showsFit, isTrue);
        expect(controller.fitWording, ProfileWording.strict);
        final fit = controller.cardFit(grill)!;
        expect(
          fit.counts,
          const VerdictCounts(
            green: 2,
            yellow: 1,
            hiddenCarbYellow: 0,
            red: 1,
            ask: 1,
          ),
        );
        expect(fit.wording, ProfileWording.strict);
        expect(controller.cardFit(sesameHouse)!.hasFittingDish, isFalse);
      },
    );

    test('a profile table: flexible, strict and a group', () async {
      final rows =
          <({String label, AppSettings settings, VerdictCounts counts})>[
            (
              label: 'lactose (flexible)',
              settings: _settingsWith(<RestrictionId>[RestrictionId.lactose]),
              counts: const VerdictCounts(
                green: 3,
                yellow: 1,
                hiddenCarbYellow: 0,
                red: 1,
              ),
            ),
            (
              label: 'sesame and lactose',
              settings: _settingsWith(<RestrictionId>[
                RestrictionId.sesame,
                RestrictionId.lactose,
              ]),
              counts: const VerdictCounts(
                green: 1,
                yellow: 1,
                hiddenCarbYellow: 0,
                red: 2,
                ask: 1,
              ),
            ),
            (
              label: 'a group: sesame for me, lactose for Dana',
              settings: AppSettings(
                profile: _profile(<RestrictionId>[RestrictionId.sesame]),
                otherProfiles: <NamedProfile>[
                  NamedProfile(
                    id: 'p1',
                    name: 'Dana',
                    profile: _profile(<RestrictionId>[RestrictionId.lactose]),
                  ),
                ],
                activeProfileIds: const <String>[NamedProfile.primaryId, 'p1'],
              ),
              counts: const VerdictCounts(
                green: 1,
                yellow: 1,
                hiddenCarbYellow: 0,
                red: 2,
                ask: 1,
              ),
            ),
          ];
      await listThree();
      for (final row in rows) {
        // Arrange
        await settings.write(row.settings);

        // Act
        await controller.load(bantoMode: true);

        // Assert
        expect(
          controller.cardFit(grill)?.counts,
          row.counts,
          reason: row.label,
        );
      }
    });

    test('an empty profile shows no fit and no chip, and keeps the keto '
        'numbers', () async {
      // Arrange
      settings = FakeSettingsStore();
      controller.dispose();
      controller = build();
      await listThree();

      // Act
      await controller.load(bantoMode: true);

      // Assert
      expect(controller.showsFit, isFalse);
      expect(controller.fitWording, ProfileWording.ketoOnly);
      expect(controller.cardFit(grill), isNull);
      expect(controller.cardNumbers(grill), isNotNull);
    });

    test('bantoMode off shows no fit, whatever the profile', () async {
      // Arrange
      await listThree();

      // Act: an explicit false, whatever the define.
      // ignore: avoid_redundant_argument_values
      await controller.load(bantoMode: false);

      // Assert
      expect(controller.showsFit, isFalse);
      expect(controller.cardFit(grill), isNull);
    });

    test('an unscored card has no fit: it stays "not scored yet"', () async {
      // Arrange
      await listThree();

      // Act
      await controller.load(bantoMode: true);

      // Assert
      expect(controller.cardNumbers(unscored), isNull);
      expect(controller.cardFit(unscored), isNull);
    });

    test(
      'a profile edited in Settings shows on the cards after load',
      () async {
        // Arrange
        await listThree();
        await controller.load(bantoMode: true);
        final before = controller.cardFit(grill)!;

        // Act
        await settings.write(
          _settingsWith(<RestrictionId>[RestrictionId.lactose]),
        );
        await controller.load(bantoMode: true);

        // Assert
        final after = controller.cardFit(grill)!;
        expect(after, isNot(before));
        expect(after.wording, ProfileWording.flexible);
        // And the same analysis is evaluated once per profile.
        expect(identical(controller.cardFit(grill), after), isTrue);
      },
    );

    group('the "Fits my profile" chip', () {
      test('hides a scored venue with no fitting dish and keeps the '
          'unscored one', () async {
        // Arrange
        await listThree();
        await controller.load(bantoMode: true);

        // Act
        controller.toggleChip(DiscoveryChip.fitsProfile);

        // Assert
        expect(controller.visibleResults, <Venue>[grill, unscored]);
        expect(controller.cardFit(unscored), isNull);
      });

      test('combines with Keto 8+, which still works', () async {
        // Arrange
        await listThree();
        await controller.load(bantoMode: true);

        // Act
        controller
          ..toggleChip(DiscoveryChip.fitsProfile)
          ..toggleChip(DiscoveryChip.ketoEightPlus);

        // Assert: Keto 8+ still hides what has no numbers, by keto score.
        for (final venue in controller.visibleResults) {
          expect(controller.cardNumbers(venue)!.score, greaterThanOrEqualTo(8));
        }
        expect(controller.visibleResults, isNot(contains(unscored)));
        expect(controller.visibleResults, isNot(contains(sesameHouse)));
      });

      test('filters nothing without a fit to read', () async {
        // Arrange
        await listThree();
        // An explicit false, whatever the define.
        // ignore: avoid_redundant_argument_values
        await controller.load(bantoMode: false);

        // Act
        controller.toggleChip(DiscoveryChip.fitsProfile);

        // Assert
        expect(controller.visibleResults, <Venue>[
          grill,
          sesameHouse,
          unscored,
        ]);
      });

      test('is turned off when the profile goes back to keto only', () async {
        // Arrange
        await listThree();
        await controller.load(bantoMode: true);
        controller.toggleChip(DiscoveryChip.fitsProfile);

        // Act
        await settings.write(const AppSettings());
        await controller.load(bantoMode: true);

        // Assert
        expect(controller.activeChips, isEmpty);
        expect(controller.visibleResults, hasLength(3));
      });
    });

    test(
      'the quick score gives a fit from its keto-only rules analysis',
      () async {
        // Arrange
        controller.dispose();
        controller = build(autoEstimateLimit: 4);
        await controller.load(bantoMode: true);
        repository.stub(grill.ref, MenuFetched(menu: _grillMenu(grill.ref)));
        search.queueFound(<Venue>[grill]);

        // Act
        await controller.locate(language: 'en');
        while (controller.isEstimating) {
          await pumpEventQueue();
        }

        // Assert: the fit, from the analysis it saved, which asked for
        // nothing beyond keto (D26 C2: the quick score stays keto-only).
        expect(controller.cardFit(grill)?.counts.green, 2);
        final saved = repository.savedAnalyses.single.analysis as MenuAnalysed;
        expect(saved.engine, isA<RulesEngine>());
        for (final dish in saved.dishes) {
          expect(dish.concerns, isEmpty);
          expect(dish.ingredients, isEmpty);
        }
      },
    );

    test('putting the nearby list back keeps its fits', () async {
      // Arrange
      await listThree();
      await controller.load(bantoMode: true);
      search.queueFound(<Venue>[unscored]);
      controller.search('other', language: 'en', immediate: true);
      await pumpEventQueue();
      expect(controller.cardFit(grill), isNull);

      // Act
      controller.clearSearch();

      // Assert
      expect(controller.cardFit(grill)?.counts.green, 2);
    });

    test('Discovery never reaches a model or the backend', () {
      // Arrange: the files the fit is computed in.
      final sources = <String>[
        'lib/state/venue_search_controller.dart',
        'lib/utils/allergens/discovery_fit.dart',
      ];

      for (final path in sources) {
        // Act
        final text = File(path).readAsStringSync();

        // Assert: no LLM client, no router, no backend client.
        expect(text, isNot(contains('services/llm/')), reason: path);
        expect(text, isNot(contains('services/menu/backend')), reason: path);
        expect(text, isNot(contains('backend_menu_classifier')), reason: path);
        expect(text, isNot(contains('routing_menu_classifier')), reason: path);
        expect(text, isNot(contains('BackendMenuAdapter')), reason: path);
      }
    });
  });
}
