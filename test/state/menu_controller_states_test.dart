// MenuController's four-state mode (Banto, ALG-05, issue #347): the
// wording, the state filter, the strict default filter, the state counts
// and the "rules checked" signal, all gated on `open`'s bantoMode.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A Hebrew menu: a tahini salad (sesame, stated in the name), a nut
/// cake (אגוזים: tree nuts likely, peanuts suspected), a pasta (not keto)
/// and a steak.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'מנות',
      dishes: <Dish>[
        _dish('salad', 'סלט עם טחינה'),
        _dish('cake', 'עוגת אגוזים'),
        _dish('pasta', 'פסטה ברוטב עגבניות'),
        _dish('steak', 'סטייק אנטריקוט'),
      ],
    ),
  ],
);

/// The verdict the fake classifier gives each dish.
AnalysedDish _verdictFor(Dish dish) => dish.id == 'pasta'
    ? AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.nonKeto,
        why: 'pasta',
      )
    : AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'why',
      );

/// A controller over [profile] whose classifier answers with [engine].
MenuController _controller(
  DietaryProfile profile, {
  AnalysisEngine engine = const LlmEngine(model: 'test-model'),
  MenuFilter? lastFilter,
}) {
  final repository = FakeMenuRepository()..stub(_ref, MenuFetched(menu: _menu));
  final classifier = FakeMenuClassifier()
    ..respondWith(
      MenuAnalysed(
        dishes: <AnalysedDish>[
          for (final dish in _menu.allDishes) _verdictFor(dish),
        ],
        unclassified: const <String>[],
        engine: engine,
        analysedAt: DateTime.utc(2026),
      ),
    );
  return MenuController(
    repository,
    classifier,
    FakeSettingsStore(
      initial: AppSettings(profile: profile, lastFilter: lastFilter),
    ),
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

/// Peanuts and sesame: a strict profile without keto.
final DietaryProfile _strict = DietaryProfile.empty
    .withEntry(RestrictionId.peanuts)
    .withEntry(RestrictionId.sesame);

/// Vegan only: a flexible profile without keto.
final DietaryProfile _flexible = DietaryProfile.empty.withEntry(
  RestrictionId.vegan,
);

List<String> _ids(MenuController controller) => <String>[
  for (final row in controller.visibleRows) row.dish.id,
];

void main() {
  group('with bantoMode off', () {
    test('a strict profile is still keto-only', () async {
      // Arrange
      final controller = _controller(_strict);

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.wording, ProfileWording.ketoOnly);
      expect(controller.evaluations, isEmpty);
      expect(controller.evaluationFor('salad'), isNull);
      expect(controller.stateCounts, VerdictCounts.zero);
      expect(controller.filter, MenuFilter.all);
      expect(controller.rulesChecked, isFalse);
      expect(_ids(controller), <String>['salad', 'cake', 'pasta', 'steak']);
    });
  });

  group('with bantoMode on', () {
    test("an empty profile is keto-only, today's filter and counts", () async {
      // Arrange
      final controller = _controller(DietaryProfile.empty);

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.wording, ProfileWording.ketoOnly);
      expect(controller.evaluations, isEmpty);
      expect(controller.filter, MenuFilter.all);
      expect(controller.redCount, 1);
    });

    test('a keto-only entry is still keto-only', () async {
      // Arrange
      final controller = _controller(
        DietaryProfile.empty.withEntry(RestrictionId.keto),
      );

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.wording, ProfileWording.ketoOnly);
      expect(controller.holdsKeto, isTrue);
    });

    test('a strict profile evaluates every analysed dish', () async {
      // Arrange
      final controller = _controller(_strict);

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.wording, ProfileWording.strict);
      expect(controller.holdsKeto, isFalse);
      expect(controller.evaluationFor('salad')?.state, DishState.avoid);
      expect(controller.evaluationFor('cake')?.state, DishState.ask);
      // Keto is not in the profile, so nothing rules the pasta out; but
      // the menu names tahini and nuts, and those kitchen signals reach
      // every dish of a strict profile (ALG-07), so it is one to ask.
      expect(controller.evaluationFor('pasta')?.state, DishState.ask);
      expect(controller.evaluationFor('steak')?.state, DishState.ask);
    });

    test('a strict profile opens on everything but avoid', () async {
      // Arrange
      final controller = _controller(_strict);

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.filter, MenuFilter.greenAndYellow);
      expect(_ids(controller), <String>['cake', 'pasta', 'steak']);
    });

    test('a last chosen filter wins over the strict default', () async {
      // Arrange
      final controller = _controller(_strict, lastFilter: MenuFilter.all);

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.filter, MenuFilter.all);
      expect(_ids(controller).length, 4);
    });

    test('a flexible profile keeps the settings default filter', () async {
      // Arrange
      final controller = _controller(_flexible);

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.wording, ProfileWording.flexible);
      expect(controller.filter, MenuFilter.all);
    });

    test('each tile filter keeps one state', () async {
      // Arrange
      final controller = _controller(_strict);
      await controller.open(_ref, bantoMode: true);

      // Act / Assert
      await controller.setFilter(MenuFilter.redOnly);
      expect(_ids(controller), <String>['salad']);
      // The tahini and nut kitchen signals turn the pasta and the steak
      // from "fits" to "ask" (ALG-07).
      await controller.setFilter(MenuFilter.askOnly);
      expect(_ids(controller), <String>['cake', 'pasta', 'steak']);
      await controller.setFilter(MenuFilter.greenOnly);
      expect(_ids(controller), isEmpty);
      await controller.setFilter(MenuFilter.yellowOnly);
      expect(_ids(controller), isEmpty);
      await controller.setFilter(MenuFilter.all);
      expect(_ids(controller).length, 4);
    });

    test('the state counts count states, the keto counts verdicts', () async {
      // Arrange
      final controller = _controller(_strict);

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(
        controller.stateCounts,
        // The pasta and the steak are "ask" through the kitchen (ALG-07).
        const VerdictCounts(
          green: 0,
          yellow: 0,
          hiddenCarbYellow: 0,
          red: 1,
          ask: 3,
        ),
      );
      expect(controller.greenCount, 3);
      expect(controller.redCount, 1);
    });

    test(
      'rules checked: a model result the rules found something in',
      () async {
        // Arrange
        final controller = _controller(_strict);

        // Act
        await controller.open(_ref, bantoMode: true);

        // Assert
        expect(controller.rulesChecked, isTrue);
      },
    );

    test('rules checked: never for a rules result', () async {
      // Arrange
      final controller = _controller(
        _strict,
        engine: const RulesEngine(reason: MenuAnalysisFailureReason.offline),
      );

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.rulesChecked, isFalse);
    });

    test('rules checked: never when nothing matches the profile', () async {
      // Arrange
      final controller = _controller(
        DietaryProfile.empty.withEntry(RestrictionId.fish),
      );

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.rulesChecked, isFalse);
    });

    test('askOnly has no keto meaning and keeps every dish', () async {
      // Arrange
      final controller = _controller(
        DietaryProfile.empty,
        lastFilter: MenuFilter.askOnly,
      );

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(_ids(controller).length, 4);
    });

    test('evaluations are computed once per menu and profile', () async {
      // Arrange
      final controller = _controller(_strict);
      await controller.open(_ref, bantoMode: true);

      // Act
      final first = controller.evaluations;
      final second = controller.evaluations;

      // Assert
      expect(identical(first, second), isTrue);
    });
  });
}
