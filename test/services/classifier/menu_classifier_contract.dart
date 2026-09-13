// The shared MenuClassifier contract (architecture.md §18.1, Liskov).
//
// Every implementation of MenuClassifier, including the fake in
// test/fakes/, is run through this suite from its own *_contract_test.dart.
// These assertions encode architecture.md's constraints 6, 7 and 8 — the
// rules that keep a wrong green rare — as executable claims. The suite is
// deliberately silent on which verdict a given dish gets: a rules engine
// and an LLM engine may legitimately disagree, so only shape and
// provenance are asserted.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';

/// The venue every menu built by this suite is addressed to.
const VenueRef _contractVenueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'menu-classifier-contract-venue',
);

/// Builds a contract-suite menu with [categories].
Menu _menuOf(List<MenuCategory> categories) => Menu(
  venueRef: _contractVenueRef,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: categories,
);

/// A menu with a couple of ordinary dishes, used by most assertions.
final Menu _populatedMenu = _menuOf(const [
  MenuCategory(
    id: 'cat-mains',
    name: 'Mains',
    dishes: [
      Dish(
        id: 'dish-salmon',
        name: 'Grilled Salmon',
        description: 'Served with lemon butter and steamed greens.',
        price: 68,
        options: [],
      ),
      Dish(
        id: 'dish-carbonara',
        name: 'Spaghetti Carbonara',
        description: 'Classic, with pancetta and egg yolk.',
        price: 54,
        options: [],
      ),
    ],
  ),
]);

/// A menu with no categories at all.
final Menu _noCategoriesMenu = _menuOf(const []);

/// A menu with one category that has no dishes.
final Menu _emptyCategoryMenu = _menuOf([
  const MenuCategory(id: 'cat-empty', name: 'Specials', dishes: []),
]);

/// Asserts the [MenuClassifier] contract against what [build] returns.
///
/// Never asserts which [DishVerdict] a dish receives — only that whatever
/// verdict comes back obeys the interface's documented invariants.
void runMenuClassifierContract(String name, MenuClassifier Function() build) {
  group(name, () {
    test('classify never throws for a menu with dishes', () async {
      final classifier = build();
      late final Future<MenuAnalysis> future;
      expect(
        () => future = classifier.classify(_populatedMenu),
        returnsNormally,
      );
      await expectLater(future, completes);
    });

    test('classify never throws for a menu with no categories', () async {
      final classifier = build();
      late final Future<MenuAnalysis> future;
      expect(
        () => future = classifier.classify(_noCategoriesMenu),
        returnsNormally,
      );
      await expectLater(future, completes);
    });

    test('classify never throws for a category with no dishes', () async {
      final classifier = build();
      late final Future<MenuAnalysis> future;
      expect(
        () => future = classifier.classify(_emptyCategoryMenu),
        returnsNormally,
      );
      await expectLater(future, completes);
    });

    test('never invents a dish id or an unclassified name', () async {
      final classifier = build();
      final result = await classifier.classify(_populatedMenu);
      if (result is MenuAnalysed) {
        final dishIds = _populatedMenu.allDishes.map((d) => d.id).toSet();
        final dishNames = _populatedMenu.allDishes.map((d) => d.name).toSet();
        for (final analysed in result.dishes) {
          expect(
            dishIds,
            contains(analysed.dishId),
            reason: 'invented dishId ${analysed.dishId}',
          );
        }
        for (final name in result.unclassified) {
          expect(
            dishNames,
            contains(name),
            reason: 'invented unclassified name "$name"',
          );
        }
      }
    });

    test(
      'a modifiable verdict always carries a non-blank modification',
      () async {
        final classifier = build();
        final result = await classifier.classify(_populatedMenu);
        if (result is MenuAnalysed) {
          for (final analysed in result.dishes) {
            if (analysed.verdict == DishVerdict.modifiable) {
              expect(
                analysed.modification,
                isNotNull,
                reason:
                    '${analysed.dishId} is modifiable with no '
                    'modification',
              );
              expect(
                analysed.modification!.trim(),
                isNotEmpty,
                reason: '${analysed.dishId} has a blank modification',
              );
            } else {
              expect(
                analysed.modification,
                isNull,
                reason:
                    '${analysed.dishId} is ${analysed.verdict} but '
                    'carries a modification',
              );
            }
          }
        }
      },
    );

    test('why is never empty on any analysed dish', () async {
      final classifier = build();
      final result = await classifier.classify(_populatedMenu);
      if (result is MenuAnalysed) {
        for (final analysed in result.dishes) {
          expect(
            analysed.why.trim(),
            isNotEmpty,
            reason: '${analysed.dishId} has an empty why',
          );
        }
      }
    });

    test('classifying the same menu twice resolves both times', () async {
      final classifier = build();
      await expectLater(classifier.classify(_populatedMenu), completes);
      await expectLater(classifier.classify(_populatedMenu), completes);
    });
  });
}
