// The one-line "This place worked for me" offer after a post-meal save, and
// the prompt that outlives the cache (Banto, issues #411 and #412): the
// offer follows a save in which every strict concern was cleared, reads in
// both languages, and never says "safe" or "בטוח"; past the cache the
// prompt asks about the dishes the visit kept.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/models/visit_dish.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/state/confirmation_controller.dart';
import 'package:ketoclub/widgets/confirmation_sheet.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hummus');

/// "safe" as a word in English, "בטוח" anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

const Dish _salad = Dish(
  id: 'salad',
  name: 'סלט חצילים',
  description: 'עם טחינה',
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

MenuAnalysed _green(List<Dish> dishes) => MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in dishes)
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

/// The stores the prompt reads: the dishes cached unless `cached` is false.
final class _Stores {
  new(List<Dish> dishes, {bool cached = true, DietaryProfile? profile})
    : settings = FakeSettingsStore(
        initial: AppSettings(
          profile:
              profile ?? DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      ) {
    if (cached) {
      repository.seedCache(
        CachedMenu(
          menu: Menu(
            venueRef: _ref,
            currency: 'ILS',
            fetchedAt: DateTime.utc(2026),
            categories: <MenuCategory>[
              MenuCategory(id: 'c', name: 'Mains', dishes: dishes),
            ],
          ),
          analysis: _green(dishes),
        ),
      );
    }
  }

  final FakeMenuRepository repository = FakeMenuRepository();
  final FakeClock clock = FakeClock(DateTime(2026, 5, 12, 20));
  late final FakeVisitHistoryStore history = FakeVisitHistoryStore(clock);
  final FakeNotesStore notes = FakeNotesStore();
  final FakeSettingsStore settings;

  ConfirmationController controller() => ConfirmationController(
    ref: _ref,
    repository: repository,
    settings: settings,
    history: history,
    notes: notes,
    clock: clock,
  );
}

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: home,
);

/// Opens the prompt over [stores]; [marked] counts the offer's taps and the
/// opened future's result lands in [result].
Future<void> _open(
  WidgetTester tester,
  _Stores stores, {
  List<bool>? result,
  List<int>? marked,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final saved = await showConfirmationSheet(
                context,
                create: stores.controller,
                bantoMode: true,
                onMarkWorked: marked == null
                    ? null
                    : () async {
                        marked.add(1);
                      },
              );
              result?.add(saved);
            },
            child: const Text('open'),
          ),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _answer(
  WidgetTester tester,
  String dishId,
  ConfirmationAnswer answer, {
  int index = 0,
}) async {
  final chip = find.byKey(confirmAnswerKey(dishId, index, answer));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(confirmSaveKey));
  await tester.tap(find.byKey(confirmSaveKey));
  await tester.pumpAndSettle();
}

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('the offer rule', () {
    Future<ConfirmationController> loaded(
      WidgetTester tester,
      _Stores stores,
    ) async {
      final controller = stores.controller();
      await stores.history.recordVisit(_ref, openedStrict: true);
      await controller.load();
      return controller;
    }

    testWidgets('holds when every strict concern is answered absent', (
      tester,
    ) async {
      // Arrange
      final controller = await loaded(tester, _Stores(<Dish>[_salad]));

      // Act
      controller.setAnswer(
        'salad',
        controller.dishes.single.concerns.single,
        ConfirmationAnswer.absent,
      );

      // Assert
      expect(workedForMeOffered(controller), isTrue);
    });

    testWidgets('is withheld for a concern not asked or confirmed present', (
      tester,
    ) async {
      // Arrange
      final controller = await loaded(tester, _Stores(<Dish>[_salad]));
      final concern = controller.dishes.single.concerns.single;

      // Act & Assert
      expect(workedForMeOffered(controller), isFalse);
      controller.setAnswer('salad', concern, ConfirmationAnswer.present);
      expect(workedForMeOffered(controller), isFalse);
    });

    testWidgets('needs every dish cleared, not just one', (tester) async {
      // Arrange
      final controller = await loaded(tester, _Stores(<Dish>[_salad, _burger]));
      controller.setAnswer(
        'salad',
        controller.dishes.first.concerns.first,
        ConfirmationAnswer.absent,
      );

      // Assert
      expect(workedForMeOffered(controller), isFalse);
    });

    testWidgets('a change made as asked clears the dish it was asked on', (
      tester,
    ) async {
      // Arrange
      final controller = await loaded(tester, _Stores(<Dish>[_burger]));
      expect(controller.dishes.single.hasChange, isTrue);

      // Act
      controller.setChange('burger', honoured: true);

      // Assert: the sesame was not asked about, the bun was changed.
      expect(workedForMeOffered(controller), isTrue);
      controller.setChange('burger', honoured: false);
      expect(workedForMeOffered(controller), isFalse);
    });

    testWidgets('does not hold for a profile with no strict restriction', (
      tester,
    ) async {
      // Arrange: lactose is an intolerance, flexible.
      final controller = await loaded(
        tester,
        _Stores(<Dish>[
          const Dish(
            id: 'cheese',
            name: 'Cheese board',
            description: 'cheese',
            price: 1,
            options: <DishOption>[],
          ),
        ], profile: DietaryProfile.empty.withEntry(RestrictionId.lactose)),
      );
      for (final item in controller.dishes) {
        for (final concern in item.concerns) {
          controller.setAnswer(
            item.dish.id,
            concern,
            ConfirmationAnswer.absent,
          );
        }
      }

      // Assert
      expect(workedForMeOffered(controller), isFalse);
    });
  });

  group('the offer in the sheet', () {
    testWidgets('appears after a save that cleared the concern, and one tap '
        'marks it', (tester) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad]);
      await stores.history.recordVisit(_ref, openedStrict: true);
      final result = <bool>[];
      final marked = <int>[];
      await _open(tester, stores, result: result, marked: marked);

      // Act
      await _answer(tester, 'salad', ConfirmationAnswer.absent);
      await _save(tester);

      // Assert: the answer is saved and the one-line offer is there.
      expect(
        (await stores.history.read(_ref))!.confirmations.single.polarity,
        ConfirmationPolarity.absent,
      );
      expect(find.text(_en.workedOffer), findsOneWidget);
      expect(find.text(_en.confirmSaved), findsOneWidget);
      expect(result, isEmpty);
      expect(_allText(tester), isNot(matches(_safe)));

      // Act
      await tester.tap(find.byKey(workedOfferKey));
      await tester.pumpAndSettle();

      // Assert
      expect(marked, <int>[1]);
      expect(result, <bool>[true]);
      expect(find.text(_en.workedOffer), findsNothing);
    });

    testWidgets('"Not now" closes without marking', (tester) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad]);
      await stores.history.recordVisit(_ref, openedStrict: true);
      final result = <bool>[];
      final marked = <int>[];
      await _open(tester, stores, result: result, marked: marked);
      await _answer(tester, 'salad', ConfirmationAnswer.absent);
      await _save(tester);

      // Act
      await tester.tap(find.byKey(workedOfferSkipKey));
      await tester.pumpAndSettle();

      // Assert
      expect(marked, isEmpty);
      expect(result, <bool>[true]);
    });

    testWidgets('is not offered when the concern was confirmed present', (
      tester,
    ) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad]);
      await stores.history.recordVisit(_ref, openedStrict: true);
      final result = <bool>[];
      await _open(tester, stores, result: result, marked: <int>[]);

      // Act
      await _answer(tester, 'salad', ConfirmationAnswer.present);
      await _save(tester);

      // Assert: the sheet just closes, as before.
      expect(find.text(_en.workedOffer), findsNothing);
      expect(result, <bool>[true]);
    });

    testWidgets('is not offered without a way to mark it', (tester) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad]);
      await stores.history.recordVisit(_ref, openedStrict: true);
      final result = <bool>[];
      await _open(tester, stores, result: result);

      // Act
      await _answer(tester, 'salad', ConfirmationAnswer.absent);
      await _save(tester);

      // Assert
      expect(find.text(_en.workedOffer), findsNothing);
      expect(result, <bool>[true]);
    });

    testWidgets('reads in Hebrew and never says בטוח', (tester) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad]);
      await stores.history.recordVisit(_ref, openedStrict: true);
      await _open(tester, stores, marked: <int>[], locale: const Locale('he'));

      // Act
      await _answer(tester, 'salad', ConfirmationAnswer.absent);
      await _save(tester);

      // Assert
      expect(find.text(_he.workedOffer), findsOneWidget);
      expect(find.text(_he.workedOfferSkip), findsOneWidget);
      expect(_allText(tester), isNot(matches(_safe)));
    });
  });

  group('the prompt past the cache', () {
    VisitDish kept(String id, String name, {bool change = false}) => VisitDish(
      dishId: id,
      name: name,
      hasChange: change,
      concerns: const <VisitConcern>[
        VisitConcern(
          restrictionId: RestrictionId.sesame,
          source: ConcernSource.description,
        ),
      ],
    );

    Future<_Stores> expired(List<VisitDish> dishes) async {
      final stores = _Stores(const <Dish>[], cached: false);
      await stores.history.recordVisit(_ref, openedStrict: true);
      final entry = (await stores.history.read(_ref))!;
      stores.history.seed(
        VisitEntry(
          ref: _ref,
          firstOpenedAt: entry.firstOpenedAt,
          lastOpenedAt: entry.lastOpenedAt,
          openCount: 1,
          openedStrict: true,
          strictDishes: dishes,
        ),
      );
      return stores;
    }

    testWidgets('lists the dishes the visit kept and records the answer under '
        'the dish id', (tester) async {
      // Arrange
      final stores = await expired(<VisitDish>[
        kept('salad', 'סלט חצילים'),
        kept('bun', 'Burger', change: true),
      ]);
      await _open(tester, stores);

      // Assert: no "no longer on this device", the dishes by name.
      expect(find.text(_en.confirmUnavailable), findsNothing);
      expect(find.text('סלט חצילים'), findsOneWidget);
      expect(find.text('Burger'), findsOneWidget);

      // Act
      await tester.tap(find.text('סלט חצילים'));
      await tester.pumpAndSettle();
      await _answer(tester, 'salad', ConfirmationAnswer.absent);
      await _save(tester);

      // Assert
      final saved = (await stores.history.read(_ref))!.confirmations.single;
      expect(saved.dishId, 'salad');
      expect(saved.restrictionId, RestrictionId.sesame);
      expect(saved.polarity, ConfirmationPolarity.absent);
      expect(saved.source, ConcernSource.description);
      expect(saved.day, DateTime(2026, 5, 12));
    });

    testWidgets('asks whether a kept change was made', (tester) async {
      // Arrange
      final stores = await expired(<VisitDish>[
        kept('bun', 'Burger', change: true),
      ]);
      await _open(tester, stores, marked: <int>[]);

      // Act: the one dish is open; the change answers the dish.
      await tester.ensureVisible(
        find.byKey(confirmChangeKey('bun', honoured: true)),
      );
      await tester.tap(find.byKey(confirmChangeKey('bun', honoured: true)));
      await tester.pump();
      await _save(tester);

      // Assert: the change was recorded, and the offer follows it.
      expect(
        (await stores.history.read(_ref))!.changeConfirmations.single.honoured,
        isTrue,
      );
      expect(find.text(_en.workedOffer), findsOneWidget);
    });

    testWidgets('a visit that kept an empty list says nothing points to the '
        'profile', (tester) async {
      // Arrange
      final stores = await expired(const <VisitDish>[]);

      // Act
      await _open(tester, stores);

      // Assert
      expect(find.text(_en.confirmNothing), findsOneWidget);
    });

    testWidgets('a visit with no list still says the menu is gone', (
      tester,
    ) async {
      // Arrange
      final stores = _Stores(const <Dish>[], cached: false);
      await stores.history.recordVisit(_ref, openedStrict: true);

      // Act
      await _open(tester, stores);

      // Assert
      expect(find.text(_en.confirmUnavailable), findsOneWidget);
    });
  });
}
