// A profile change re-evaluates from the cached extraction with no network
// call (Banto; ALG-03, issue #345, "the big win of option B"). The real
// LlmMenuClassifier runs over a fake chat client that counts requests: one
// request when the menu opens, none when the profile changes afterwards,
// while the dish's state follows the new profile.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_llm_chat_client.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';

/// The venue the test opens.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A salad whose text names neither sesame nor milk: only the model's
/// ingredient list says what is in it.
const Dish _salad = Dish(
  id: 'salad',
  name: 'House salad',
  description: '',
  price: 40,
  options: <DishOption>[],
);

/// The menu the repository serves.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(id: 'c1', name: 'Salads', dishes: <Dish>[_salad]),
  ],
);

/// The model's reply: green for keto, with a tahini dressing and a feta
/// garnish in the extraction.
final String _reply = jsonEncode(<String, Object?>{
  'dishes': <Object?>[
    <String, Object?>{
      'id': _salad.id,
      'name': _salad.name,
      'verdict': 'orderAsIs',
      'why': 'Leaves and dressing.',
      'modification': null,
      'net_carbs_estimate': null,
      'hidden_carbs': const <Object?>[],
      'ingredients': const <Object?>[
        <String, Object?>{
          'name': 'tahini',
          'certainty': 'likely',
          'role': 'sauce',
        },
        <String, Object?>{
          'name': 'feta cheese',
          'certainty': 'likely',
          'role': 'garnish',
        },
      ],
    },
  ],
});

void main() {
  test(
    'changing the profile re-evaluates the dish with no new request',
    () async {
      // Arrange
      final chat = FakeLlmChatClient()
        ..enqueue(ChatCompleted(content: _reply, model: 'test-model'));
      final settings = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );
      final controller = MenuController(
        FakeMenuRepository()..stub(_ref, MenuFetched(menu: _menu)),
        LlmMenuClassifier(chat, FakeClock(DateTime.utc(2026))),
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
      );
      await controller.open(_ref, bantoMode: true);
      final before = controller.evaluationFor(_salad.id)!;

      // Act: add milk in Settings and come back to the menu.
      await settings.write(
        (await settings.read()).copyWith(
          profile: DietaryProfile.empty
              .withEntry(RestrictionId.sesame)
              .withEntry(RestrictionId.milk),
        ),
      );
      await controller.refreshProfile();
      final after = controller.evaluationFor(_salad.id)!;

      // Act: then drop sesame.
      await settings.write(
        (await settings.read()).copyWith(
          profile: DietaryProfile.empty.withEntry(RestrictionId.milk),
        ),
      );
      await controller.refreshProfile();
      final milkOnly = controller.evaluationFor(_salad.id)!;

      // Assert: one request, and it asked for the extraction.
      expect(chat.requests, hasLength(1));
      expect(
        chat.requests.single.responseSchema.toString(),
        contains('ingredients'),
      );

      // Assert: the state followed each profile from the one extraction.
      // The text does not name them, so the parser caps both at suspected
      // and a strict entry asks (D26, ALG-03's support cap).
      expect(before.state, DishState.ask);
      expect(
        before.concerns.map((concern) => concern.restrictionId),
        <RestrictionId>[RestrictionId.sesame],
      );
      expect(after.state, DishState.ask);
      expect(
        after.concerns.map((concern) => concern.restrictionId).toSet(),
        <RestrictionId>{RestrictionId.sesame, RestrictionId.milk},
      );
      expect(
        milkOnly.concerns.map((concern) => concern.restrictionId),
        <RestrictionId>[RestrictionId.milk],
      );
    },
  );
}
