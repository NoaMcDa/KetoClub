// Group profiles in the two controllers (Banto; ALG-12, #354):
// SettingsController adds, renames, edits and deletes people and picks
// who a menu is read for; MenuController evaluates once per person and
// shows the strictest state, with each person's kept for the breakdown.
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
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/profile_wording.dart';

import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every menu test opens.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A cheese omelette (milk, stated in the name) and a steak.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        _dish('omelette', 'Cheese omelette'),
        _dish('steak', 'Tomato salad'),
      ],
    ),
  ],
);

/// Dana, holding milk.
final NamedProfile _dana = NamedProfile(
  id: 'p1',
  name: 'Dana',
  profile: DietaryProfile.empty.withEntry(RestrictionId.milk),
);

/// A menu controller over [settings], every dish green from the model.
MenuController _menuController(FakeSettingsStore settings, {Menu? menu}) {
  final served = menu ?? _menu;
  final repository = FakeMenuRepository()
    ..stub(_ref, MenuFetched(menu: served));
  final classifier = FakeMenuClassifier()
    ..respondWith(
      MenuAnalysed(
        dishes: <AnalysedDish>[
          for (final dish in served.allDishes)
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
      ),
    );
  return MenuController(
    repository,
    classifier,
    settings,
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

void main() {
  group('SettingsController group profiles', () {
    late FakeSettingsStore store;
    late SettingsController controller;

    setUp(() async {
      store = FakeSettingsStore();
      controller = SettingsController(store, FakeMenuRepository());
      await controller.load();
    });

    test('starts with the one primary profile, active', () {
      // Assert
      expect(controller.profiles.single.isPrimary, isTrue);
      expect(controller.activeProfiles.single.isPrimary, isTrue);
      expect(controller.canAddProfile, isTrue);
    });

    test('addProfile gives p1, p2 and does not combine them', () async {
      // Act
      final first = await controller.addProfile('  Dana ');
      final second = await controller.addProfile('Grandma');

      // Assert
      expect(first, 'p1');
      expect(second, 'p2');
      expect(controller.profiles.map((named) => named.name).toList(), <String>[
        '',
        'Dana',
        'Grandma',
      ]);
      expect(controller.activeProfiles.single.isPrimary, isTrue);
      expect((await store.read()).otherProfiles, hasLength(2));
    });

    test('addProfile refuses a blank name and a full device', () async {
      // Act
      final blank = await controller.addProfile('   ');
      for (var i = 1; i < NamedProfile.maxProfiles; i++) {
        await controller.addProfile('P$i');
      }
      final over = await controller.addProfile('One too many');

      // Assert
      expect(blank, isNull);
      expect(over, isNull);
      expect(controller.profiles, hasLength(NamedProfile.maxProfiles));
      expect(controller.canAddProfile, isFalse);
    });

    test('a freed id is reused, keeping ids deterministic', () async {
      // Arrange
      await controller.addProfile('Dana');
      await controller.addProfile('Grandma');
      await controller.deleteProfile('p1');

      // Act
      final id = await controller.addProfile('Uri');

      // Assert
      expect(id, 'p1');
    });

    test('renames another person, refusing a blank name', () async {
      // Arrange
      final id = (await controller.addProfile('Dana'))!;

      // Act
      await controller.renameProfile(id, 'Dana (8)');
      await controller.renameProfile(id, '  ');

      // Assert
      expect(controller.profileById(id)!.name, 'Dana (8)');
    });

    test('renames the primary, and a blank name restores "Me"', () async {
      // Act
      await controller.renameProfile(NamedProfile.primaryId, 'Noa');
      final named = controller.profiles.first.name;
      await controller.renameProfile(NamedProfile.primaryId, '');

      // Assert
      expect(named, 'Noa');
      expect(controller.profiles.first.name, isEmpty);
      expect((await store.read()).toJson().containsKey('profileName'), isFalse);
    });

    test('edits another person without touching the primary', () async {
      // Arrange
      final id = (await controller.addProfile('Dana'))!;

      // Act
      await controller.addRestrictionTo(id, RestrictionId.milk);
      await controller.addRestrictionTo(id, RestrictionId.eggs);
      await controller.removeRestrictionFrom(id, RestrictionId.eggs);

      // Assert
      expect(
        controller.profileById(id)!.profile.entries.single.restrictionId,
        RestrictionId.milk,
      );
      expect(controller.profile, DietaryProfile.empty);
    });

    test('editing the primary through its id is the old setter', () async {
      // Act
      await controller.addRestrictionTo(
        NamedProfile.primaryId,
        RestrictionId.sesame,
      );

      // Assert
      expect(controller.profile.contains(RestrictionId.sesame), isTrue);
      await controller.removeRestrictionFrom(
        NamedProfile.primaryId,
        RestrictionId.sesame,
      );
      expect(controller.profile, DietaryProfile.empty);
    });

    test('setActiveProfiles keeps profile order and refuses none', () async {
      // Arrange
      final id = (await controller.addProfile('Dana'))!;

      // Act
      await controller.setActiveProfiles(<String>[id, 'me', 'gone']);
      final both = controller.activeProfiles.map((named) => named.id);
      await controller.setActiveProfiles(const <String>[]);

      // Assert
      expect(both, <String>['me', id]);
      expect(controller.activeProfiles, hasLength(2));
    });

    test('deleting an active person drops them from the active set', () async {
      // Arrange
      final id = (await controller.addProfile('Dana'))!;
      await controller.setActiveProfiles(<String>[id]);

      // Act
      await controller.deleteProfile(id);
      await controller.deleteProfile(NamedProfile.primaryId);

      // Assert
      expect(controller.profiles.single.isPrimary, isTrue);
      expect(controller.activeProfiles.single.isPrimary, isTrue);
      expect(
        (await store.read()).activeProfileIds,
        AppSettings.defaultActiveProfileIds,
      );
    });
  });

  group('MenuController group evaluation', () {
    test("one person: no breakdown, and today's evaluation", () async {
      // Arrange
      final controller = _menuController(
        FakeSettingsStore(initial: AppSettings(profile: _dana.profile)),
      );

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.isGroup, isFalse);
      expect(controller.breakdownFor('omelette'), isNull);
      expect(controller.evaluationFor('omelette')!.state, DishState.avoid);
    });

    test('milk + keto: the omelette is avoid, with each person kept', () async {
      // Arrange
      final controller = _menuController(
        FakeSettingsStore(
          initial: AppSettings(
            otherProfiles: <NamedProfile>[_dana],
            activeProfileIds: const <String>['me', 'p1'],
          ),
        ),
      );

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert
      expect(controller.isGroup, isTrue);
      expect(controller.wording, ProfileWording.strict);
      expect(controller.holdsKeto, isTrue);
      expect(controller.evaluationFor('omelette')!.state, DishState.avoid);
      final breakdown = controller.breakdownFor('omelette')!;
      expect(
        breakdown.map((person) => (person.person.id, person.state)),
        <(String, DishState)>[('me', DishState.fits), ('p1', DishState.avoid)],
      );
      expect(controller.evaluationFor('steak')!.state, DishState.fits);
      expect(controller.stateCounts.green, 1);
      // The strict default hides what to avoid; show everything.
      await controller.setFilter(MenuFilter.all);
      expect(controller.evaluatedRows, hasLength(2));
      expect(
        controller.evaluatedRows
            .firstWhere((row) => row.row.dish.id == 'omelette')
            .evaluated
            .state,
        DishState.avoid,
      );
    });

    test('each person gets the heading and the kitchen pass', () async {
      // Arrange: fries share a fryer with the fried bread; Me is celiac
      // and Dana keto.
      final menu = Menu(
        venueRef: _ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: <MenuCategory>[
          MenuCategory(
            id: 'c1',
            name: 'Mains',
            dishes: <Dish>[
              _dish('fries', 'French fries'),
              _dish('bread', 'Fried bread'),
            ],
          ),
        ],
      );
      final controller = _menuController(
        FakeSettingsStore(
          initial: AppSettings(
            profile: DietaryProfile.empty.withEntry(RestrictionId.gluten),
            otherProfiles: const <NamedProfile>[
              NamedProfile(id: 'p1', name: 'Dana'),
            ],
            activeProfileIds: const <String>['me', 'p1'],
            lastFilter: MenuFilter.all,
          ),
        ),
        menu: menu,
      );

      // Act
      await controller.open(_ref, bantoMode: true);

      // Assert: the fryer makes the fries an "ask" for Me only.
      expect(
        controller.breakdownFor('fries')!.map((person) => person.state),
        <DishState>[DishState.ask, DishState.fits],
      );
      expect(controller.evaluationFor('fries')!.state, DishState.ask);
      expect(
        controller.evaluatedRows
            .firstWhere((row) => row.row.dish.id == 'fries')
            .evaluated
            .state,
        DishState.ask,
      );
    });

    test('setActiveProfiles saves the choice and re-evaluates', () async {
      // Arrange
      final settings = FakeSettingsStore(
        initial: AppSettings(otherProfiles: <NamedProfile>[_dana]),
      );
      final controller = _menuController(settings);
      await controller.open(_ref, bantoMode: true);
      final before = controller.wording;

      // Act
      await controller.setActiveProfiles(<String>['me', 'p1', 'gone']);

      // Assert
      expect(before, ProfileWording.ketoOnly);
      expect(controller.people.map((named) => named.id), <String>['me', 'p1']);
      expect(controller.allProfiles, hasLength(2));
      expect(controller.evaluationFor('omelette')!.state, DishState.avoid);
      expect((await settings.read()).activeProfileIds, <String>['me', 'p1']);
    });

    test('an empty choice is ignored', () async {
      // Arrange
      final settings = FakeSettingsStore(
        initial: AppSettings(otherProfiles: <NamedProfile>[_dana]),
      );
      final controller = _menuController(settings);
      await controller.open(_ref, bantoMode: true);
      final writes = settings.writeCallCount;

      // Act
      await controller.setActiveProfiles(const <String>['gone']);

      // Assert
      expect(controller.people.single.isPrimary, isTrue);
      expect(settings.writeCallCount, writes);
    });

    test('refreshProfile picks up a person added in Settings', () async {
      // Arrange
      final settings = FakeSettingsStore();
      final controller = _menuController(settings);
      await controller.open(_ref, bantoMode: true);
      await settings.write(
        AppSettings(
          otherProfiles: <NamedProfile>[_dana],
          activeProfileIds: const <String>['me', 'p1'],
        ),
      );
      var notified = 0;
      controller.addListener(() => notified++);

      // Act
      await controller.refreshProfile();
      await controller.refreshProfile();

      // Assert
      expect(notified, 1);
      expect(controller.isGroup, isTrue);
      expect(controller.breakdownFor('omelette'), hasLength(2));
    });

    test('a group with milk asks for ingredients; a keto pair does not', () {
      // Arrange
      const keto = AppSettings(
        otherProfiles: <NamedProfile>[NamedProfile(id: 'p1', name: 'A')],
        activeProfileIds: <String>['me', 'p1'],
      );
      final milk = AppSettings(
        otherProfiles: <NamedProfile>[_dana],
        activeProfileIds: const <String>['me', 'p1'],
      );

      // Act + Assert
      expect(keto.activeHasNonKetoEntry, isFalse);
      expect(milk.activeHasNonKetoEntry, isTrue);
    });
  });
}
