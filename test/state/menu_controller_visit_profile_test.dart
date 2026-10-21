// MenuController and the Recent tab's per-profile fields (Banto, issues
// #411 and #412): an open under a profile records the state counts, the
// fingerprint and the strict dishes with the visit, an open without one
// records nothing new, and the venue can be marked as having worked for the
// people the menu is read for.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/visit_profile.dart';

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
        Dish(
          id: 'steak',
          name: 'סטייק',
          description: '',
          price: 90,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

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
          AnalysedDish(
            dishId: 'steak',
            name: 'סטייק',
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

  group('the visit under a profile', () {
    test('records the counts, the fingerprint and the strict dishes', () async {
      // Arrange
      final controller = _controller(AppSettings(profile: _sesame), history);

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      final entry = (await history.read(_ref))!;
      expect(entry.hasStates, isTrue);
      // The steak has nothing found; the tahini salad is stated sesame.
      expect(entry.fits, 1);
      expect(entry.withChange! + entry.ask! + entry.avoid!, 1);
      expect(entry.profileFingerprint, profileFingerprintOf(_sesame));
      final dish = entry.strictDishes!.single;
      expect(dish.dishId, 'salad');
      expect(dish.name, 'סלט עם טחינה');
      expect(dish.concerns.single.restrictionId, RestrictionId.sesame);
    });

    test('a second open replaces them with the profile as it is now', () async {
      // Arrange
      await _controller(
        AppSettings(profile: _sesame),
        history,
      ).open(_ref, bantoMode: true);
      final both = _sesame.withEntry(RestrictionId.peanuts);

      // Act
      await _controller(
        AppSettings(profile: both),
        history,
      ).open(_ref, bantoMode: true);

      // Assert
      expect(
        (await history.read(_ref))!.profileFingerprint,
        profileFingerprintOf(both),
      );
    });

    test('a keto build records nothing new', () async {
      // Arrange
      final controller = _controller(AppSettings(profile: _sesame), history);

      // Act
      await controller.open(_ref); // No define.

      // Assert
      expect(history.recordCalls.single.snapshot, isNull);
      expect((await history.read(_ref))!.hasStates, isFalse);
    });

    test('a keto-only profile records nothing new, even in Banto', () async {
      // Arrange
      final controller = _controller(const AppSettings(), history);

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(history.recordCalls.single.snapshot, isNull);
      expect((await history.read(_ref))!.strictDishes, isNull);
    });

    test('a flexible profile records counts but no strict dishes', () async {
      // Arrange
      final controller = _controller(
        AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.lactose),
        ),
        history,
      );

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      final entry = (await history.read(_ref))!;
      expect(entry.hasStates, isTrue);
      expect(entry.strictDishes, isEmpty);
    });
  });

  group('Worked for me', () {
    test(
      'marks the venue for the person, shows the tag, and unmarks',
      () async {
        // Arrange
        final controller = _controller(AppSettings(profile: _sesame), history);
        await controller.open(_ref, bantoMode: true);
        expect(controller.canMarkWorked, isTrue);
        expect(controller.isWorkedFor, isFalse);

        // Act
        await controller.setWorkedForMe(worked: true);

        // Assert
        expect(controller.isWorkedFor, isTrue);
        expect(controller.workedForPeople, <String>[workedForSelf]);
        expect((await history.read(_ref))!.workedFor, <String>[workedForSelf]);

        // Act
        await controller.setWorkedForMe(worked: false);

        // Assert
        expect(controller.isWorkedFor, isFalse);
        expect((await history.read(_ref))!.workedFor, isEmpty);
      },
    );

    test('a reopened venue is still marked', () async {
      // Arrange
      final first = _controller(AppSettings(profile: _sesame), history);
      await first.open(_ref, bantoMode: true);
      await first.setWorkedForMe(worked: true);

      // Act
      final again = _controller(AppSettings(profile: _sesame), history);
      await again.open(_ref, bantoMode: true);

      // Assert
      expect(again.isWorkedFor, isTrue);
    });

    test('in a group it marks everyone the menu is read for', () async {
      // Arrange
      final dana = NamedProfile(
        id: 'dana',
        name: 'Dana',
        profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
      );
      final controller = _controller(
        AppSettings(
          profile: _sesame,
          primaryProfileName: 'Noa',
          otherProfiles: <NamedProfile>[dana],
          activeProfileIds: const <String>[NamedProfile.primaryId, 'dana'],
        ),
        history,
      );
      await controller.open(_ref, bantoMode: true);

      // Act
      await controller.setWorkedForMe(worked: true);

      // Assert
      expect(controller.workedForPeople, <String>['Noa', 'Dana']);
    });

    test('is unavailable without Banto or under a keto-only profile', () async {
      // Arrange
      final keto = _controller(AppSettings(profile: _sesame), history);
      await keto.open(_ref);
      final bare = _controller(const AppSettings(), history);
      await bare.open(_ref, bantoMode: true);

      // Act
      await keto.setWorkedForMe(worked: true);
      await bare.setWorkedForMe(worked: true);

      // Assert
      expect(keto.canMarkWorked, isFalse);
      expect(bare.canMarkWorked, isFalse);
      expect(history.workedCalls, isEmpty);
    });
  });
}
