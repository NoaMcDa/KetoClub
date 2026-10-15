// MenuController and the restaurant's allergen matrix (Banto; ALG-16,
// related to #358): the matrix that came with the fetch is matched against
// the menu, its rows reach the evaluations, and without Banto, without a
// matrix or outside its dates nothing changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/allergen_matrix.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/allergen_matrix.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// Three dishes with no allergen word in their text.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 10, 15),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        _dish('shak', 'Tomato stew'),
        _dish('bowl', 'Green bowl'),
        _dish('steak', 'Steak'),
      ],
    ),
  ],
);

/// Shakshuka contains eggs, the bowl may contain sesame; a pizza row
/// matches nothing.
AllergenMatrix _matrix({DateTime? validUntil}) => AllergenMatrix(
  source: MatrixSource.restaurant,
  validFrom: DateTime.utc(2026, 10),
  validUntil: validUntil,
  rows: const <AllergenMatrixRow>[
    AllergenMatrixRow(
      name: 'תבשיל עגבניות',
      aliases: <String>['Tomato stew'],
      cells: <RestrictionId, MatrixCell>{
        RestrictionId.eggs: MatrixCell.contains,
      },
    ),
    AllergenMatrixRow(
      name: 'Green bowl',
      cells: <RestrictionId, MatrixCell>{
        RestrictionId.sesame: MatrixCell.mayContain,
      },
    ),
    AllergenMatrixRow(name: 'Pizza'),
  ],
);

final DietaryProfile _profile = DietaryProfile.empty
    .withEntry(RestrictionId.eggs)
    .withEntry(RestrictionId.sesame);

MenuController _controller(AllergenMatrix? matrix, {AppSettings? settings}) {
  final repository = FakeMenuRepository()
    ..stub(_ref, MenuFetched(menu: _menu, allergenMatrix: matrix));
  final classifier = FakeMenuClassifier()
    ..respondWith(
      MenuAnalysed(
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
        analysedAt: DateTime.utc(2026, 10, 15),
      ),
    );
  return MenuController(
    repository,
    classifier,
    FakeSettingsStore(
      initial:
          settings ??
          AppSettings(profile: _profile, lastFilter: MenuFilter.all),
    ),
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

void main() {
  test('the matrix reaches the evaluations and lists its stray row', () async {
    // Arrange
    final controller = _controller(_matrix());

    // Act
    await controller.open(_ref, bantoMode: true);

    // Assert
    expect(controller.allergenMatrix, _matrix());
    final match = controller.allergenMatrixMatch!;
    expect(match.rowsByDishId.keys, unorderedEquals(<String>['shak', 'bowl']));
    expect(match.unmatched.single.row.name, 'Pizza');
    expect(match.unmatched.single.reason, UnmatchedReason.noDish);
    expect(controller.evaluationFor('shak')?.state, DishState.avoid);
    expect(
      controller.evaluationFor('shak')?.concerns.single.source,
      ConcernSource.matrix,
    );
    expect(controller.evaluationFor('bowl')?.state, DishState.ask);
    expect(controller.evaluationFor('steak')?.state, DishState.fits);
    // The rows the screen shows carry the same evaluation.
    final rows = {
      for (final entry in controller.evaluatedRows)
        entry.row.dish.id: entry.evaluated.state,
    };
    expect(rows, {
      'shak': DishState.avoid,
      'bowl': DishState.ask,
      'steak': DishState.fits,
    });
    // Asked twice, the match is the same object.
    expect(identical(controller.allergenMatrixMatch, match), isTrue);
  });

  test('a group carries the matrix to each person', () async {
    // Arrange: the owner avoids eggs, a friend sesame.
    final controller = _controller(
      _matrix(),
      settings: AppSettings(
        profile: DietaryProfile.empty.withEntry(RestrictionId.eggs),
        otherProfiles: <NamedProfile>[
          NamedProfile(
            id: 'friend',
            name: 'Omer',
            profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
          ),
        ],
        activeProfileIds: const <String>[NamedProfile.primaryId, 'friend'],
        lastFilter: MenuFilter.all,
      ),
    );

    // Act
    await controller.open(_ref, bantoMode: true);

    // Assert
    expect(controller.isGroup, isTrue);
    expect(controller.evaluationFor('shak')?.state, DishState.avoid);
    expect(controller.evaluationFor('bowl')?.state, DishState.ask);
    final rows = {
      for (final entry in controller.evaluatedRows)
        entry.row.dish.id: entry.evaluated.state,
    };
    expect(rows['shak'], DishState.avoid);
  });

  test('without Banto the matrix is not there', () async {
    // Arrange
    final controller = _controller(_matrix());

    // Act
    await controller.open(_ref);

    // Assert
    expect(controller.allergenMatrix, isNull);
    expect(controller.allergenMatrixMatch, isNull);
    expect(controller.evaluations, isEmpty);
  });

  test('a matrix past its last day on the fetch day is not applied', () async {
    // Arrange: it ended the day before the menu was fetched.
    final controller = _controller(
      _matrix(validUntil: DateTime.utc(2026, 10, 14)),
    );

    // Act
    await controller.open(_ref, bantoMode: true);

    // Assert
    expect(controller.allergenMatrix, isNull);
    expect(controller.evaluationFor('shak')?.state, DishState.fits);
  });

  test('no matrix leaves every dish to the menu text', () async {
    // Arrange
    final controller = _controller(null);

    // Act
    await controller.open(_ref, bantoMode: true);

    // Assert
    expect(controller.allergenMatrixMatch, isNull);
    expect(controller.evaluationFor('shak')?.state, DishState.fits);
  });

  test('a failed open forgets the matrix', () async {
    // Arrange
    final repository = FakeMenuRepository()
      ..stub(_ref, MenuFetched(menu: _menu, allergenMatrix: _matrix()));
    final controller = MenuController(
      repository,
      FakeMenuClassifier(),
      FakeSettingsStore(initial: AppSettings(profile: _profile)),
      FakeNotesStore(),
      CarbBudgetController(),
    );
    await controller.open(_ref, bantoMode: true);
    repository.stub(
      _ref,
      const MenuFetchFailed(reason: MenuFetchFailureReason.notFound),
    );

    // Act
    await controller.open(_ref, bantoMode: true);

    // Assert
    expect(controller.allergenMatrix, isNull);
  });

  test('a refresh takes the matrix the new fetch carried', () async {
    // Arrange
    final repository = FakeMenuRepository()
      ..stub(_ref, MenuFetched(menu: _menu, allergenMatrix: _matrix()));
    final controller = MenuController(
      repository,
      FakeMenuClassifier(),
      FakeSettingsStore(initial: AppSettings(profile: _profile)),
      FakeNotesStore(),
      CarbBudgetController(),
    );
    await controller.open(_ref, bantoMode: true);
    expect(controller.allergenMatrix, isNotNull);
    repository.stub(_ref, MenuFetched(menu: _menu));

    // Act
    await controller.refresh();

    // Assert
    expect(controller.allergenMatrix, isNull);
  });
}
