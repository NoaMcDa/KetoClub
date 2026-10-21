// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, issue #410): with a sesame
// allergy in the profile, Discovery answers "does this place work for
// me?" on each card. The venues come from a Wolt discovery page (the
// `pages/restaurants` shape of `test/fixtures/wolt_pages_restaurants.json`,
// read by the real `WoltVenueMapper`); their menus are stubbed and scored
// by the real on-device rule engine (the quick score, D21). Each scored
// card shows "N no trigger found · M with a change · K to ask" instead of
// the keto score, and "Fits my profile" hides the venue none of whose
// dishes fits, while the venue that could not be scored stays, unlabelled.
// The effect spans Settings' stored profile, the quick score and the
// cards, which is why this is a flow and not a widget test.
//
// The second test wires a phone build with a backend (D25) and checks
// that Discovery's fit adds no backend or model request: the menus come
// from Wolt directly, as the quick score always read them.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/services/venue/wolt/wolt_venue_mapper.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// One venue item of a Wolt `pages/restaurants` section, as the fixture
/// writes it.
Map<String, Object?> _woltItem(String slug, String name) => <String, Object?>{
  'title': name,
  'template': 'venue-large',
  'track_id': 'venue-$slug',
  'venue': <String, Object?>{
    'slug': slug,
    'name': name,
    'city': 'Tel Aviv',
    'location': <double>[34.7806, 32.0809],
    'tags': <String>['grill'],
    'online': true,
    'estimate': 20,
  },
};

/// A Wolt discovery page with three venues and a promo tile the mapper
/// skips.
final Map<String, Object?> _woltPage = <String, Object?>{
  'city': 'tel-aviv',
  'sections': <Object?>[
    <String, Object?>{
      'name': 'restaurants-delivering-venues',
      'items': <Object?>[
        <String, Object?>{'title': 'Free delivery', 'template': 'banner'},
        _woltItem('banto-grill', 'Banto Grill'),
        _woltItem('sesame-house', 'Sesame House'),
        _woltItem('quiet-cafe', 'Quiet Cafe'),
      ],
    },
  ],
};

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

/// The grill's dishes: nothing for sesame, tahini as a removable sauce,
/// falafel (a suspected source: ask) and a sesame-crusted steak.
final List<Dish> _grillDishes = <Dish>[
  _dish('salmon', 'Grilled salmon', 'With a green salad'),
  _dish(
    'chicken',
    'Chicken skewers',
    'With a choice of sauce',
    options: const <DishOption>[
      DishOption(name: 'Sauce', values: <String>['Tahini', 'Garlic']),
    ],
  ),
  _dish('falafel', 'Falafel plate', 'With chopped salad'),
  _dish('steak', 'Steak', 'Sesame crusted'),
];

/// [dishes] as [ref]'s menu.
Menu _menu(VenueRef ref, List<Dish> dishes) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'mains', name: 'Mains', dishes: dishes),
  ],
);

/// The settings of a user with a sesame allergy, past the first run.
final AppSettings _sesameSettings = AppSettings(
  profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
  onboardingSeen: true,
  disclosureSeen: true,
);

/// Scrolls [finder] into view, then taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto Discovery flow', () {
    testWidgets('a sesame profile: the cards count what fits, and "Fits my '
        'profile" filters', (tester) async {
      // Setup: the Wolt page's venues; the grill and the sesame house have
      // menus, the cafe's cannot be read.
      final venues = WoltVenueMapper.map(_woltPage)!;
      expect(venues.map((venue) => venue.name), <String>[
        'Banto Grill',
        'Sesame House',
        'Quiet Cafe',
      ]);
      final grill = venues[0];
      final sesameHouse = venues[1];
      final fakes = FakeAppDependencies();
      fakes.venueSearchService.result = VenuesFound(venues);
      fakes.repository
        ..stub(grill.ref, MenuFetched(menu: _menu(grill.ref, _grillDishes)))
        ..stub(
          sesameHouse.ref,
          MenuFetched(
            menu: _menu(sesameHouse.ref, <Dish>[
              _dish('steak', 'Steak', 'Sesame crusted'),
              _dish('tuna', 'Seared tuna', 'Rolled in sesame seeds'),
            ]),
          ),
        );
      await fakes.settingsStore.write(_sesameSettings);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: list the venues nearby; the quick score runs on its own.
      await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

      // Assert: the grill counts 1 · 1 · 1 and the sesame house 0 · 0 · 0
      // in the strict wording; no keto score is shown.
      expect(find.text(_en.headerStateCountsStrict(1, 1, 1)), findsOneWidget);
      expect(find.text(_en.headerStateCountsStrict(0, 0, 0)), findsOneWidget);
      expect(find.text('10.0'), findsNothing);
      expect(find.text('Quiet Cafe'), findsOneWidget);
      // Keto 8+ is still there beside the new chip.
      expect(
        find.widgetWithText(FilterChip, _en.discoveryChipKetoEightPlus),
        findsOneWidget,
      );

      // Act
      await _tap(
        tester,
        find.widgetWithText(FilterChip, _en.discoveryChipFitsProfile),
      );

      // Assert: the sesame house is gone; the unscored cafe stays.
      expect(find.text('Banto Grill'), findsOneWidget);
      expect(find.text('Sesame House'), findsNothing);
      expect(find.text('Quiet Cafe'), findsOneWidget);
      // The rule engine scored the cards; the menu screen's classifier
      // (the router, which would reach the model) was never asked.
      expect(fakes.classifier.calls, isEmpty);
    });

    testWidgets('with a backend, the fit asks neither the backend nor the '
        'model for anything', (tester) async {
      // Setup: a phone build with a backend; every venue serves the
      // grill's menu from Wolt.
      const slug = 'banto-grill';
      const ref = VenueRef(source: MenuSource.wolt, platformId: slug);
      final network = FlowBackendNetwork(
        menu: _menu(ref, _grillDishes),
        venues: const <Venue>[Venue(ref: ref, name: 'Banto Grill')],
      );
      final fakes = FakeAppDependencies();
      wireBackendBuild(fakes, network.client);
      await fakes.settingsStore.write(_sesameSettings);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act
      await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));

      // Assert: the card counts the fit (the scripted assortment carries
      // no options, so the chicken's tahini sauce is not on it and the
      // chicken fits as it is)…
      expect(find.text(_en.headerStateCountsStrict(2, 0, 1)), findsOneWidget);
      // …from a menu read on Wolt directly, with no menu, classify or
      // chat route on the backend and no request to the model.
      expect(network.pathsTo(flowWoltHost), isNotEmpty);
      final backendPaths = network.pathsTo(flowBackendHost);
      expect(backendPaths, isNot(contains(startsWith('/v1/venue-menus'))));
      expect(backendPaths, isNot(contains('/v1/classify')));
      expect(backendPaths, isNot(contains('/v1/chat')));
      expect(network.pathsTo(flowGeminiHost), isEmpty);
    });
  });
}
