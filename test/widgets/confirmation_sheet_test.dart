// The post-meal prompt and the dated staff answers on the dish (Banto,
// ALG-14, issue #356): the sheet's questions and answers, the Recent row's
// action, the Why sheet's "you confirmed with the staff on …" line and the
// dish card's words — and never "safe" or "בטוח".
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
import 'package:ketoclub/screens/saved_screen.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/confirmation_controller.dart';
import 'package:ketoclub/state/saved_controller.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/widgets/confirmation_sheet.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/why_sheet.dart';
import 'package:provider/provider.dart';

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

/// Every dish of [dishes] placed green.
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

/// The stores the prompt reads, with the given dishes cached and analysed.
final class _Stores {
  new(List<Dish> dishes, {this.cached = true}) {
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

  final bool cached;
  final FakeMenuRepository repository = FakeMenuRepository();
  final FakeClock clock = FakeClock(DateTime(2026, 5, 12, 20));
  late final FakeVisitHistoryStore history = FakeVisitHistoryStore(clock);
  final FakeNotesStore notes = FakeNotesStore();
  final FakeSettingsStore settings = FakeSettingsStore(
    initial: AppSettings(
      profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
    ),
  );

  ConfirmationController controller(VenueRef ref) => ConfirmationController(
    ref: ref,
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

/// Pumps a button that opens the prompt over [stores]; the opened future's
/// result lands in [result].
Future<void> _pumpOpener(
  WidgetTester tester,
  _Stores stores, {
  Locale locale = const Locale('en'),
  bool bantoMode = true,
  List<bool>? result,
}) async {
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final saved = await showConfirmationSheet(
                context,
                create: () => stores.controller(_ref),
                bantoMode: bantoMode,
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

/// Every [Text] on screen, joined.
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('the prompt', () {
    testWidgets('asks per concern with three answers and saves one', (
      tester,
    ) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad]);
      await stores.history.recordVisit(_ref, openedStrict: true);
      final result = <bool>[];
      await _pumpOpener(tester, stores, result: result);

      // Assert: the one dish is open on its question and three answers.
      expect(find.text(_en.confirmPromptTitle), findsOneWidget);
      expect(
        find.text(_en.confirmPromptQuestion('Sesame', _salad.name)),
        findsOneWidget,
      );
      expect(find.text(_en.confirmAnswerPresent), findsOneWidget);
      expect(find.text(_en.confirmAnswerAbsent), findsOneWidget);
      expect(find.text(_en.confirmAnswerNotAsked), findsOneWidget);
      expect(find.text(_en.confirmChangeQuestion), findsNothing);
      expect(_allText(tester), isNot(matches(_safe)));

      // Act
      await tester.tap(
        find.byKey(confirmAnswerKey('salad', 0, ConfirmationAnswer.present)),
      );
      await tester.pump();
      await tester.enterText(find.byKey(confirmNoteKey('salad')), 'Asked');
      await tester.tap(find.byKey(confirmSaveKey));
      await tester.pumpAndSettle();

      // Assert
      expect(result, <bool>[true]);
      final entry = await stores.history.read(_ref);
      expect(
        entry?.confirmations.single.polarity,
        ConfirmationPolarity.present,
      );
      expect(entry?.confirmations.single.day, DateTime(2026, 5, 12));
      expect(await stores.notes.read(_ref, 'salad'), 'Asked');
    });

    testWidgets('asks whether the change was made, and a tap takes it back', (
      tester,
    ) async {
      // Arrange
      final stores = _Stores(<Dish>[_burger, _salad]);
      await stores.history.recordVisit(_ref, openedStrict: true);
      await _pumpOpener(tester, stores);

      // Act: two dishes start collapsed; open the burger.
      await tester.tap(find.text('Burger'));
      await tester.pumpAndSettle();
      final yes = find.byKey(confirmChangeKey('burger', honoured: true));
      final no = find.byKey(confirmChangeKey('burger', honoured: false));
      await tester.ensureVisible(no);
      await tester.tap(yes);
      await tester.pump();
      await tester.tap(no);
      await tester.pump();
      await tester.tap(no);
      await tester.pump();
      await tester.tap(yes);
      await tester.pump();
      await tester.ensureVisible(find.byKey(confirmSaveKey));
      await tester.tap(find.byKey(confirmSaveKey));
      await tester.pumpAndSettle();

      // Assert
      expect(
        (await stores.history.read(_ref))?.changeConfirmations.single.honoured,
        isTrue,
      );
    });

    testWidgets('reads in Hebrew and never says בטוח', (tester) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad]);
      await stores.history.recordVisit(_ref, openedStrict: true);

      // Act
      await _pumpOpener(tester, stores, locale: const Locale('he'));

      // Assert
      expect(
        find.text(_he.confirmPromptQuestion('שומשום', _salad.name)),
        findsOneWidget,
      );
      expect(find.text(_he.confirmAnswerNotAsked), findsOneWidget);
      expect(_allText(tester), isNot(matches(_safe)));
    });

    testWidgets('says so when nothing on the menu points to the profile', (
      tester,
    ) async {
      // Arrange
      const steak = Dish(
        id: 'steak',
        name: 'Steak',
        description: '',
        price: 90,
        options: <DishOption>[],
      );
      final stores = _Stores(<Dish>[steak]);
      await stores.history.recordVisit(_ref, openedStrict: true);

      // Act
      await _pumpOpener(tester, stores);

      // Assert
      expect(find.text(_en.confirmNothing), findsOneWidget);
      expect(find.byKey(confirmSaveKey), findsNothing);
    });

    testWidgets('says so when the menu is no longer on the device', (
      tester,
    ) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad], cached: false);
      await stores.history.recordVisit(_ref, openedStrict: true);

      // Act
      await _pumpOpener(tester, stores);

      // Assert
      expect(find.text(_en.confirmUnavailable), findsOneWidget);
    });

    testWidgets('opens nothing with bantoMode off', (tester) async {
      // Arrange
      final stores = _Stores(<Dish>[_salad]);
      final result = <bool>[];

      // Act
      await _pumpOpener(tester, stores, bantoMode: false, result: result);

      // Assert
      expect(find.text(_en.confirmPromptTitle), findsNothing);
      expect(result, <bool>[false]);
    });
  });

  group('the Recent row', () {
    Future<_Stores> pumpRecent(
      WidgetTester tester, {
      required bool strict,
      bool bantoMode = true,
      bool cached = true,
    }) async {
      // A fresh tree, so each call builds its own controller.
      await tester.pumpWidget(const SizedBox());
      final stores = _Stores(<Dish>[_salad], cached: cached);
      await stores.history.recordVisit(
        _ref,
        name: 'Hummus Bar',
        openedStrict: strict,
      );
      await tester.pumpWidget(
        _app(
          ChangeNotifierProvider<SavedController>(
            create: (_) => SavedController(stores.repository, stores.history),
            child: SavedScreen(
              bantoMode: bantoMode,
              createConfirmations: stores.controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return stores;
    }

    testWidgets('offers the prompt for a menu opened with a strict entry', (
      tester,
    ) async {
      // Arrange
      await pumpRecent(tester, strict: true);

      // Act
      await tester.tap(find.text(_en.confirmPromptOpen));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(confirmAnswerKey('salad', 0, ConfirmationAnswer.absent)),
      );
      await tester.pump();
      await tester.tap(find.byKey(confirmSaveKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.confirmSaved), findsOneWidget);
    });

    testWidgets('offers nothing without a strict open, banto or a copy', (
      tester,
    ) async {
      // Act & Assert
      await pumpRecent(tester, strict: false);
      expect(find.text(_en.confirmPromptOpen), findsNothing);
      await pumpRecent(tester, strict: true, bantoMode: false);
      expect(find.text(_en.confirmPromptOpen), findsNothing);
      await pumpRecent(tester, strict: true, cached: false);
      expect(find.text(_en.confirmPromptOpen), findsNothing);
    });
  });

  group('the dated answer on the dish', () {
    const confirmed = Concern(
      restrictionId: RestrictionId.sesame,
      source: ConcernSource.description,
      certainty: Certainty.stated,
      tier: EvidenceTier.confirmed,
      matchedText: 'טחינה',
    );
    const denied = Concern(
      restrictionId: RestrictionId.sesame,
      source: ConcernSource.description,
      certainty: Certainty.suspected,
      tier: EvidenceTier.denied,
      matchedText: 'טחינה',
    );
    ConfirmationEvidence piece(ConfirmationPolarity polarity) =>
        ConfirmationEvidence(
          restrictionId: RestrictionId.sesame,
          polarity: polarity,
          day: DateTime(2026, 5, 12),
        );

    testWidgets('the Why sheet says when the staff confirmed it', (
      tester,
    ) async {
      // Act
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: WhySheet(
              dishName: _salad.name,
              concerns: const <Concern>[confirmed],
              strictProfile: true,
              confirmations: <ConfirmationEvidence>[
                piece(ConfirmationPolarity.present),
              ],
              bantoMode: true,
            ),
          ),
        ),
      );

      // Assert
      expect(find.byKey(whyConfirmationKey(0)), findsOneWidget);
      expect(
        find.text('You confirmed with the staff on May 12'),
        findsOneWidget,
      );
    });

    testWidgets('the Why sheet dates a denial in Hebrew, still asking', (
      tester,
    ) async {
      // Act
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: WhySheet(
              dishName: _salad.name,
              concerns: const <Concern>[denied],
              strictProfile: true,
              confirmations: <ConfirmationEvidence>[
                piece(ConfirmationPolarity.absent),
              ],
              bantoMode: true,
            ),
          ),
          locale: const Locale('he'),
        ),
      );

      // Assert
      expect(find.text(_he.whyDeniedOn(DateTime(2026, 5, 12))), findsOneWidget);
      expect(_he.whyDeniedOn(DateTime(2026, 5, 12)), contains('12 במאי'));
      expect(_allText(tester), isNot(matches(_safe)));
    });

    test('a concern no answer moved, or a shared one, has no date line', () {
      // Act & Assert
      expect(
        whyConfirmationLine(_en, confirmed, const <ConfirmationEvidence>[]),
        isNull,
      );
      const stated = Concern(
        restrictionId: RestrictionId.sesame,
        source: ConcernSource.name,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
      );
      expect(
        whyConfirmationLine(_en, stated, <ConfirmationEvidence>[
          piece(ConfirmationPolarity.present),
        ]),
        isNull,
      );
      expect(
        whyConfirmationLine(_en, confirmed, <ConfirmationEvidence>[
          ConfirmationEvidence(
            restrictionId: RestrictionId.sesame,
            polarity: ConfirmationPolarity.present,
            day: DateTime(2026, 5, 12),
            shared: true,
            count: 5,
          ),
        ]),
        isNull,
      );
    });

    test('the dish card words the dated answers', () {
      // Act
      final yes = concernCertaintyText(
        _en,
        confirmed,
        confirmations: <ConfirmationEvidence>[
          piece(ConfirmationPolarity.present),
        ],
      );
      final no = concernCertaintyText(
        _he,
        denied,
        confirmations: <ConfirmationEvidence>[
          piece(ConfirmationPolarity.absent),
        ],
      );
      final plain = concernCertaintyText(_en, denied);

      // Assert
      expect(yes, 'you confirmed it with the staff, May 12');
      expect(no, _he.concernDeniedOn(DateTime(2026, 5, 12)));
      expect(no, isNot(matches(_safe)));
      expect(plain, _en.concernCertaintySuspected);
    });
  });
}
