// ConfirmationController (Banto, ALG-14, issue #356): the post-meal prompt
// lists the dishes the profile has a concern about, records answers with
// the visit history stamped with today's date, writes nothing for "didn't
// ask", and keeps notes in the NotesStore.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/confirmation_controller.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hummus');

/// A dish named [name] with [id] and [description].
Dish _dish(String id, String name, {String description = ''}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 40,
  options: const <DishOption>[],
);

final Dish _salad = _dish('salad', 'סלט חצילים', description: 'עם טחינה');
final Dish _steak = _dish('steak', 'Steak');

/// A dish the analysis never placed: the prompt cannot ask about it.
final Dish _unplaced = _dish('bun', 'Burger', description: 'sesame bun');

final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c',
      name: 'Mains',
      dishes: <Dish>[_salad, _steak, _unplaced],
    ),
  ],
);

final MenuAnalysed _analysis = MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in <Dish>[_salad, _steak])
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

final DateTime _now = DateTime(2026, 5, 12, 21, 30);

void main() {
  late FakeMenuRepository repository;
  late FakeVisitHistoryStore history;
  late FakeNotesStore notes;
  late FakeSettingsStore settings;
  late FakeClock clock;

  ConfirmationController build() => ConfirmationController(
    ref: _ref,
    repository: repository,
    settings: settings,
    history: history,
    notes: notes,
    clock: clock,
  );

  setUp(() async {
    repository = FakeMenuRepository()
      ..seedCache(CachedMenu(menu: _menu, analysis: _analysis));
    clock = FakeClock(_now);
    history = FakeVisitHistoryStore(clock);
    await history.recordVisit(_ref, openedStrict: true);
    notes = FakeNotesStore();
    settings = FakeSettingsStore(
      initial: AppSettings(
        profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
      ),
    );
  });

  test('load lists only the analysed dishes with a concern', () async {
    // Arrange
    final controller = build();

    // Act
    await controller.load();

    // Assert: the steak has no concern and the burger no analysis.
    expect(controller.isLoading, isFalse);
    expect(controller.isAvailable, isTrue);
    expect(controller.dishes.map((item) => item.dish.id), <String>['salad']);
    final concern = controller.dishes.single.concerns.single;
    expect(concern.restrictionId, RestrictionId.sesame);
    expect(controller.answerFor('salad', concern), ConfirmationAnswer.notAsked);
  });

  test('save records the answer with today, never the time', () async {
    // Arrange
    final controller = build();
    await controller.load();
    final concern = controller.dishes.single.concerns.single;

    // Act
    controller.setAnswer('salad', concern, ConfirmationAnswer.absent);
    final wrote = await controller.save();

    // Assert
    expect(wrote, isTrue);
    final entry = await history.read(_ref);
    expect(entry?.confirmations, <DishConfirmation>[
      DishConfirmation(
        dishId: 'salad',
        restrictionId: RestrictionId.sesame,
        polarity: ConfirmationPolarity.absent,
        day: DateTime(2026, 5, 12),
        source: concern.source,
        matchedText: concern.matchedText,
      ),
    ]);
  });

  test("didn't ask writes nothing", () async {
    // Arrange
    final controller = build();
    await controller.load();

    // Act
    final wrote = await controller.save();

    // Assert
    expect(wrote, isFalse);
    expect(history.confirmationCalls, isEmpty);
    expect((await history.read(_ref))?.confirmations, isEmpty);
  });

  test("today's answer reopens and can be taken back", () async {
    // Arrange
    final first = build();
    await first.load();
    final concern = first.dishes.single.concerns.single;
    first.setAnswer('salad', concern, ConfirmationAnswer.present);
    await first.save();

    // Act
    final again = build();
    await again.load();
    final shown = again.answerFor('salad', concern);
    again.setAnswer('salad', concern, ConfirmationAnswer.notAsked);
    await again.save();

    // Assert
    expect(shown, ConfirmationAnswer.present);
    expect((await history.read(_ref))?.confirmations, isEmpty);
  });

  test("an earlier day's answer is history and is kept", () async {
    // Arrange
    final earlier = DishConfirmation(
      dishId: 'salad',
      restrictionId: RestrictionId.sesame,
      polarity: ConfirmationPolarity.present,
      day: DateTime(2026, 4),
    );
    await history.setConfirmations(
      _ref,
      confirmations: <DishConfirmation>[earlier],
      changes: const <ChangeConfirmation>[],
    );
    final controller = build();
    await controller.load();
    final concern = controller.dishes.single.concerns.single;

    // Act
    final shown = controller.answerFor('salad', concern);
    controller.setAnswer('salad', concern, ConfirmationAnswer.absent);
    await controller.save();

    // Assert
    expect(shown, ConfirmationAnswer.notAsked);
    final stored = (await history.read(_ref))!.confirmations;
    expect(stored, hasLength(2));
    expect(stored.first, earlier);
    expect(stored.last.polarity, ConfirmationPolarity.absent);
  });

  test('records whether the change was made, for a dish with one', () async {
    // Arrange: a burger whose bun is only an option, so it is a change.
    const burger = Dish(
      id: 'burger',
      name: 'Burger',
      description: '',
      price: 50,
      options: <DishOption>[
        DishOption(name: 'Bun', values: <String>['sesame bun']),
      ],
    );
    repository.seedCache(
      CachedMenu(
        menu: Menu(
          venueRef: _ref,
          currency: 'ILS',
          fetchedAt: DateTime.utc(2026),
          categories: const <MenuCategory>[
            MenuCategory(id: 'c', name: 'Mains', dishes: <Dish>[burger]),
          ],
        ),
        analysis: MenuAnalysed(
          dishes: const <AnalysedDish>[
            AnalysedDish(
              dishId: 'burger',
              name: 'Burger',
              verdict: DishVerdict.orderAsIs,
              why: 'Fits',
            ),
          ],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: DateTime.utc(2026),
        ),
      ),
    );
    final controller = build();
    await controller.load();

    // Act
    final hasChange = controller.dishes.single.hasChange;
    controller.setChange('burger', honoured: false);
    await controller.save();
    controller.setChange('burger', honoured: null);

    // Assert
    expect(hasChange, isTrue);
    expect(controller.changeFor('burger'), isNull);
    expect((await history.read(_ref))?.changeConfirmations, [
      ChangeConfirmation(
        dishId: 'burger',
        honoured: false,
        day: DateTime(2026, 5, 12),
      ),
    ]);
  });

  test('a note is written, kept as is, and cleared when blank', () async {
    // Arrange
    final controller = build();
    await controller.load();

    // Act
    controller.setNote('salad', '  Asked twice, they checked  ');
    await controller.save();
    final kept = controller.noteFor('salad');
    controller.setNote('salad', '   ');
    await controller.save();

    // Assert
    expect(kept, 'Asked twice, they checked');
    expect(notes.writeCalls.single.note, 'Asked twice, they checked');
    expect(notes.deleteCalls.single.dishId, 'salad');
    expect(await notes.read(_ref, 'salad'), isNull);
  });

  test('is unavailable when the cached menu has gone', () async {
    // Arrange
    repository = FakeMenuRepository();
    final controller = build();

    // Act
    await controller.load();
    final wrote = await controller.save();

    // Assert
    expect(controller.isAvailable, isFalse);
    expect(controller.dishes, isEmpty);
    expect(wrote, isFalse);
  });

  test('is unavailable when the menu has no history entry', () async {
    // Arrange
    history = FakeVisitHistoryStore(clock);
    final controller = build();

    // Act
    await controller.load();

    // Assert
    expect(controller.isAvailable, isFalse);
  });

  test('the concern asked about is the menu text, before any answer', () async {
    // Arrange: a stored denial would lower the concern on the menu
    // screen; the prompt still asks about what the menu says.
    await history.setConfirmations(
      _ref,
      confirmations: <DishConfirmation>[
        DishConfirmation(
          dishId: 'salad',
          restrictionId: RestrictionId.sesame,
          polarity: ConfirmationPolarity.absent,
          day: DateTime(2026, 4),
        ),
      ],
      changes: const <ChangeConfirmation>[],
    );
    final controller = build();

    // Act
    await controller.load();

    // Assert
    expect(
      controller.dishes.single.concerns.single.tier,
      isNot(EvidenceTier.denied),
    );
  });
}
