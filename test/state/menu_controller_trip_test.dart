// MenuController under trip mode (Banto, ALG-13, issue #355): the stored
// destination's lexicon reaches the on-device evaluations only with the
// opening screen's bantoMode on, is picked up again when the user comes back
// from Settings, and never changes what is classified.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A Tokyo menu: yakisoba (wheat, by the Japanese lexicon only) and a
/// green salad.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'JPY',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'yakisoba',
          name: 'Yakisoba',
          description: '',
          price: 900,
          options: <DishOption>[],
        ),
        Dish(
          id: 'salad',
          name: 'Green salad',
          description: '',
          price: 1200,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// Every dish green.
final MenuAnalysed _analysis = MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in _menu.allDishes)
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'why',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'test-model'),
  analysedAt: DateTime.utc(2026),
);

/// Whether [controller] holds yakisoba's wheat concern from the Japanese
/// lexicon: a hidden source, suspected. (The menu's kitchen may add a
/// suspected wheat concern of its own, ALG-07, so the state alone does
/// not tell the trip's from the kitchen's.)
bool _tripWheat(MenuController controller) =>
    controller
        .evaluationFor('yakisoba')
        ?.concerns
        .any(
          (concern) =>
              concern.restrictionId == RestrictionId.wheat &&
              concern.source == ConcernSource.hidden &&
              concern.certainty == Certainty.suspected,
        ) ??
    false;

/// A wheat allergy.
final DietaryProfile _wheat = DietaryProfile.empty.withEntry(
  RestrictionId.wheat,
);

/// A controller whose settings hold [settings]; also answers its classifier.
({
  MenuController controller,
  FakeMenuClassifier classifier,
  FakeSettingsStore store,
})
_controller(AppSettings settings) {
  final repository = FakeMenuRepository()..stub(_ref, MenuFetched(menu: _menu));
  final classifier = FakeMenuClassifier()..respondWith(_analysis);
  final store = FakeSettingsStore(initial: settings);
  return (
    controller: MenuController(
      repository,
      classifier,
      store,
      FakeNotesStore(),
      CarbBudgetController(),
    ),
    classifier: classifier,
    store: store,
  );
}

void main() {
  test('with a trip to Japan, yakisoba is a dish to ask about', () async {
    final (:controller, classifier: _, store: _) = _controller(
      AppSettings(profile: _wheat, tripDestination: TripDestination.japan),
    );

    await controller.open(_ref, bantoMode: true);

    expect(controller.trip, TripDestination.japan);
    expect(_tripWheat(controller), isTrue);
    expect(controller.evaluationFor('yakisoba')?.state, DishState.ask);
    expect(
      controller.evaluationFor('salad')?.concerns.map((c) => c.source),
      isNot(contains(ConcernSource.hidden)),
    );
  });

  test('with no trip, yakisoba carries no lexicon concern', () async {
    final (:controller, classifier: _, store: _) = _controller(
      AppSettings(profile: _wheat),
    );

    await controller.open(_ref, bantoMode: true);

    expect(controller.trip, isNull);
    expect(controller.evaluationFor('yakisoba'), isNotNull);
    expect(_tripWheat(controller), isFalse);
  });

  test('a keto-only screen never reads the trip', () async {
    final (:controller, classifier: _, store: _) = _controller(
      AppSettings(profile: _wheat, tripDestination: TripDestination.japan),
    );

    // The build's flag, off under plain `flutter test`.
    await controller.open(_ref);

    expect(controller.trip, isNull);
    expect(controller.evaluations, isEmpty);
  });

  test('switching the trip off in Settings re-evaluates on refreshProfile, '
      'with no new classification', () async {
    final (:controller, :classifier, :store) = _controller(
      AppSettings(profile: _wheat, tripDestination: TripDestination.japan),
    );
    await controller.open(_ref, bantoMode: true);
    final calls = classifier.calls.length;
    expect(_tripWheat(controller), isTrue);

    await store.write((await store.read()).copyWith(tripDestination: null));
    await controller.refreshProfile();

    expect(controller.trip, isNull);
    expect(_tripWheat(controller), isFalse);
    expect(classifier.calls.length, calls);
  });

  test('the trip leaves the classification options untouched', () async {
    final withTrip = _controller(
      AppSettings(profile: _wheat, tripDestination: TripDestination.japan),
    );
    final without = _controller(AppSettings(profile: _wheat));

    await withTrip.controller.open(_ref, bantoMode: true);
    await without.controller.open(_ref, bantoMode: true);

    expect(
      withTrip.classifier.calls.single.$2,
      without.classifier.calls.single.$2,
    );
  });
}
