// ConfirmationController's opt-in sharing (Banto, ALG-14, issue #409):
// with "Share what the staff told you" on and a backend configured, saving
// the post-meal prompt also sends each newly recorded answer, one fact per
// call; off, or with no backend, nothing is sent. The note, the change
// answer and an answer about the user's own words never are, and a
// failure leaves the answer on the device.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/community/confirmation_client.dart'
    as community;
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/confirmation_controller.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_confirmation_client.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hummus');

/// Sesame in the description; a kiwi the user's own word matches; a
/// sesame bun only as an option, so it carries a change.
const Dish _salad = Dish(
  id: 'salad',
  name: 'סלט חצילים',
  description: 'עם טחינה וקיווי',
  price: 40,
  options: <DishOption>[],
);

const Dish _burger = Dish(
  id: 'burger',
  name: 'Burger',
  description: '',
  price: 50,
  options: <DishOption>[
    DishOption(name: 'Bun', values: <String>['sesame bun']),
  ],
);

final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(id: 'c', name: 'Mains', dishes: <Dish>[_salad, _burger]),
  ],
);

final MenuAnalysed _analysis = MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in <Dish>[_salad, _burger])
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'Fits',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'test-model'),
  analysedAt: DateTime.utc(2026),
);

void main() {
  late FakeMenuRepository repository;
  late FakeVisitHistoryStore history;
  late FakeNotesStore notes;
  late FakeSettingsStore settings;
  late FakeConfirmationClient client;

  /// The profile: sesame, plus the user's own word "קיווי".
  final profile = DietaryProfile.empty
      .withEntry(RestrictionId.sesame)
      .withCustomTerm('קיווי');

  ConfirmationController build() => ConfirmationController(
    ref: _ref,
    repository: repository,
    settings: settings,
    history: history,
    notes: notes,
    clock: FakeClock(DateTime(2026, 5, 12, 21, 30)),
    sharing: client,
  );

  /// Loads a prompt and answers every concern with [answer].
  Future<ConfirmationController> answered(ConfirmationAnswer answer) async {
    final controller = build();
    await controller.load();
    for (final item in controller.dishes) {
      for (final concern in item.concerns) {
        controller.setAnswer(item.dish.id, concern, answer);
      }
      if (item.hasChange) controller.setChange(item.dish.id, honoured: true);
      controller.setNote(item.dish.id, 'they checked with the chef');
    }
    return controller;
  }

  setUp(() async {
    repository = FakeMenuRepository()
      ..seedCache(CachedMenu(menu: _menu, analysis: _analysis));
    history = FakeVisitHistoryStore(FakeClock(DateTime(2026, 5, 12)));
    await history.recordVisit(_ref, openedStrict: true);
    notes = FakeNotesStore();
    client = FakeConfirmationClient();
    settings = FakeSettingsStore(
      initial: AppSettings(profile: profile, shareConfirmations: true),
    );
  });

  test('sharing off sends nothing', () async {
    // Arrange
    settings = FakeSettingsStore(initial: AppSettings(profile: profile));
    final controller = await answered(ConfirmationAnswer.absent);

    // Act
    final wrote = await controller.save();
    await controller.lastShare;

    // Assert
    expect(wrote, isTrue);
    expect(client.calls, isEmpty);
  });

  test('sharing on without a backend sends nothing', () async {
    // Arrange
    client.isConfigured = false;
    final controller = await answered(ConfirmationAnswer.absent);

    // Act
    await controller.save();
    await controller.lastShare;

    // Assert
    expect(client.calls, isEmpty);
  });

  test(
    'sharing on sends one fact per shareable answer, nothing else',
    () async {
      // Arrange
      final controller = await answered(ConfirmationAnswer.absent);

      // Act
      await controller.save();
      await controller.lastShare;

      // Assert: the salad's and the burger's sesame, never the user's own
      // word, the change answer or the note.
      final stored = (await history.read(_ref))!.confirmations;
      expect(
        stored.where((c) => c.restrictionId == RestrictionId.custom),
        isNotEmpty,
      );
      expect(client.calls, hasLength(2));
      expect(
        client.calls.map((call) => call.dishFingerprint),
        unorderedEquals(<String>[
          dishFingerprint('salad'),
          dishFingerprint('burger'),
        ]),
      );
      for (final call in client.calls) {
        expect(call.ref, _ref);
        expect(call.restrictionId, RestrictionId.sesame.name);
        expect(call.polarity, community.ConfirmationPolarity.absent);
      }
    },
  );

  test('saving again sends only what changed today', () async {
    // Arrange
    final controller = await answered(ConfirmationAnswer.absent);
    await controller.save();
    await controller.lastShare;
    client.calls.clear();

    // Act: an unchanged save, then one answer corrected.
    await controller.save();
    await controller.lastShare;
    final unchanged = List<FakeConfirmationCall>.of(client.calls);
    final salad = controller.dishes.firstWhere((d) => d.dish.id == 'salad');
    controller.setAnswer(
      'salad',
      salad.concerns.firstWhere((c) => c.restrictionId == RestrictionId.sesame),
      ConfirmationAnswer.present,
    );
    await controller.save();
    await controller.lastShare;

    // Assert
    expect(unchanged, isEmpty);
    expect(client.calls, hasLength(1));
    expect(client.calls.single.dishFingerprint, dishFingerprint('salad'));
    expect(
      client.calls.single.polarity,
      community.ConfirmationPolarity.present,
    );
  });

  test('a failed send leaves the answer on the device', () async {
    // Arrange
    client.result = const community.ConfirmationFailed(
      reason: community.ConfirmationFailureReason.backendUnreachable,
    );
    final controller = await answered(ConfirmationAnswer.present);

    // Act
    final wrote = await controller.save();
    await controller.lastShare;

    // Assert
    expect(wrote, isTrue);
    expect(client.calls, hasLength(2));
    final stored = (await history.read(_ref))!.confirmations;
    expect(
      stored.where((c) => c.polarity == ConfirmationPolarity.present),
      hasLength(3),
    );
  });

  test('without a client nothing is sent and lastShare completes', () async {
    // Arrange
    final controller = ConfirmationController(
      ref: _ref,
      repository: repository,
      settings: settings,
      history: history,
      notes: notes,
      clock: FakeClock(DateTime(2026, 5, 12)),
    );
    await controller.load();

    // Act & Assert
    await controller.lastShare;
    expect(await controller.save(), isFalse);
  });
}
