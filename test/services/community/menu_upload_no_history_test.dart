// The shared menu store's upload carries nothing of the visit history
// (Banto, issues #411 and #412; architecture.md D23, D24, D26 C1): not the
// state counts, the profile fingerprint, the strict dishes, the "worked for"
// people, the post-meal answers or the strict flag. `MenuUpload.toJson` is
// exactly the venue, its names, the menu and the analysis, and a Banto open
// under a profile, with a mark on the venue, uploads that and no more.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/community/menu_store_client.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_menu_classifier.dart';
import '../../fakes/fake_menu_repository.dart';
import '../../fakes/fake_menu_store_client.dart';
import '../../fakes/fake_notes_store.dart';
import '../../fakes/fake_settings_store.dart';
import '../../fakes/fake_visit_history_store.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'salad',
          name: 'Tahini salad',
          description: '',
          price: 10,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// Every key the visit history adds to an entry, in quotes as JSON writes it.
const List<String> _historyKeys = <String>[
  '"workedFor"',
  '"fits"',
  '"withChange"',
  '"ask"',
  '"avoid"',
  '"profileFingerprint"',
  '"strictDishes"',
  '"openedStrict"',
  '"confirmations"',
  '"changeConfirmations"',
  '"firstOpenedAt"',
  '"lastOpenedAt"',
  '"openCount"',
];

void main() {
  test('MenuUpload.toJson is the venue, its names, the menu and the '
      'analysis, nothing else', () {
    // Act
    final json = MenuUpload(ref: _ref, menu: _menu).toJson();

    // Assert
    expect(json.keys.toSet(), <String>{
      'source',
      'platform_id',
      'venue_name',
      'city',
      'menu',
      'analysis',
    });
  });

  test('a Banto open under a profile, on a marked venue, uploads no history '
      'field and no restriction', () async {
    // Arrange: consent given, a store that takes uploads, a sesame profile.
    final history = FakeVisitHistoryStore(FakeClock(DateTime.utc(2026)));
    final store = FakeMenuStoreClient();
    final repository = FakeMenuRepository()
      ..stub(_ref, MenuFetched(menu: _menu));
    final classifier = FakeMenuClassifier()
      ..respondWith(
        MenuAnalysed(
          dishes: const <AnalysedDish>[
            AnalysedDish(
              dishId: 'salad',
              name: 'Tahini salad',
              verdict: DishVerdict.orderAsIs,
              why: 'Fits',
            ),
          ],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: DateTime.utc(2026),
        ),
      );
    final controller = MenuController(
      repository,
      classifier,
      FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      ),
      FakeNotesStore(),
      CarbBudgetController(),
      null,
      history,
      store,
    );

    // Act
    await controller.open(_ref, bantoMode: true);
    await controller.setWorkedForMe(worked: true);
    await controller.lastUpload;

    // Assert: the history holds the fields, the upload names none of them.
    final entry = (await history.read(_ref))!;
    expect(entry.hasStates, isTrue);
    expect(entry.workedFor, isNotEmpty);
    expect(store.uploads, isNotEmpty);
    for (final upload in store.uploads) {
      final body = jsonEncode(upload.toJson());
      for (final key in _historyKeys) {
        expect(body, isNot(contains(key)), reason: key);
      }
      expect(body, isNot(contains('sesame')));
      expect(body, isNot(contains(entry.profileFingerprint)));
    }
  });
}
