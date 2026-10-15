// MenuController and the post-meal answers (Banto, ALG-14, issue #356):
// a strict open marks the visit for the Recent prompt, and the answers
// recorded with the visit re-tier the dish the next time the menu opens.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'מנות',
      dishes: <Dish>[
        Dish(
          id: 'salad',
          name: 'סלט עם טחינה',
          description: '',
          price: 10,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

/// A controller over [settings] whose history is [history].
MenuController _controller(
  AppSettings settings,
  FakeVisitHistoryStore history,
) {
  final repository = FakeMenuRepository()..stub(_ref, MenuFetched(menu: _menu));
  final classifier = FakeMenuClassifier()
    ..respondWith(
      MenuAnalysed(
        dishes: const <AnalysedDish>[
          AnalysedDish(
            dishId: 'salad',
            name: 'סלט עם טחינה',
            verdict: DishVerdict.orderAsIs,
            why: 'why',
          ),
        ],
        unclassified: const <String>[],
        engine: const LlmEngine(model: 'test-model'),
        analysedAt: DateTime.utc(2026),
      ),
    );
  return MenuController(
    repository,
    classifier,
    FakeSettingsStore(initial: settings),
    FakeNotesStore(),
    CarbBudgetController(),
    null,
    history,
  );
}

void main() {
  late FakeVisitHistoryStore history;

  setUp(() {
    history = FakeVisitHistoryStore(FakeClock(DateTime.utc(2026)));
  });

  test('a strict Banto open marks the visit for the prompt', () async {
    // Arrange
    final controller = _controller(AppSettings(profile: _sesame), history);

    // Act
    await controller.open(_ref, bantoMode: true);

    // Assert
    expect(history.recordCalls.single.openedStrict, isTrue);
  });

  test('a keto build never marks it', () async {
    // Arrange
    final controller = _controller(AppSettings(profile: _sesame), history);

    // Act
    await controller.open(_ref); // No define: the keto build.

    // Assert
    expect(history.recordCalls.single.openedStrict, isFalse);
    expect(
      (await history.read(_ref))?.toJson().keys,
      isNot(contains('openedStrict')),
    );
  });

  test('the next open shows the dish at the staff answer', () async {
    // Arrange: the menu was opened, then the staff said "no sesame".
    await history.recordVisit(_ref, openedStrict: true);
    await history.setConfirmations(
      _ref,
      confirmations: <DishConfirmation>[
        DishConfirmation(
          dishId: 'salad',
          restrictionId: RestrictionId.sesame,
          polarity: ConfirmationPolarity.absent,
          day: DateTime(2026, 5, 12),
        ),
      ],
      changes: const <ChangeConfirmation>[],
    );
    final controller = _controller(AppSettings(profile: _sesame), history);

    // Act
    await controller.open(_ref, bantoMode: true);
    final evaluated = controller.evaluationFor('salad')!;
    final rows = controller.evaluatedRows;

    // Assert: denied, and for an allergen still to ask about.
    expect(evaluated.concerns.single.tier, EvidenceTier.denied);
    expect(evaluated.state, DishState.ask);
    expect(evaluated.confirmations.single.day, DateTime(2026, 5, 12));
    expect(rows.single.evaluated.state, DishState.ask);
  });

  test('a group reads the answers for every person', () async {
    // Arrange
    await history.recordVisit(_ref);
    await history.setConfirmations(
      _ref,
      confirmations: <DishConfirmation>[
        DishConfirmation(
          dishId: 'salad',
          restrictionId: RestrictionId.sesame,
          polarity: ConfirmationPolarity.present,
          day: DateTime(2026, 5, 12),
        ),
      ],
      changes: const <ChangeConfirmation>[],
    );
    final settings = AppSettings(
      profile: _sesame,
      otherProfiles: <NamedProfile>[
        NamedProfile(
          id: 'p1',
          name: 'Dana',
          profile: DietaryProfile.empty.withEntry(RestrictionId.lactose),
        ),
      ],
      activeProfileIds: const <String>['me', 'p1'],
    );
    final controller = _controller(settings, history);

    // Act
    await controller.open(_ref, bantoMode: true);

    // Assert
    final evaluated = controller.evaluationFor('salad')!;
    expect(evaluated.concerns.single.tier, EvidenceTier.confirmed);
    expect(evaluated.state, DishState.avoid);
    expect(evaluated.confirmations, isNotEmpty);
  });
}
