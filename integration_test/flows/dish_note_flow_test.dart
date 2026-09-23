// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #52):
// a personal note written on a dish shows on its card and survives a
// revisit of the same venue — through the flow fake `NotesStore`, never
// through a controller reached from the side.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/note_editor_sheet.dart';

import 'flow_support.dart';

/// The Wolt venue page the user pastes, in the documented
/// `wolt.com/{lang}/{country}/{city}/restaurant/{slug}` form
/// (architecture.md §6.5 Tier A).
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum';

/// The [VenueRef] [_woltUrl] resolves to, and the key the fakes below are
/// stubbed under.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'vitrina-lilinblum',
);

/// The note this journey writes.
const String _note = 'Waitstaff happily substituted cauliflower.';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// One [Menu] with a single green dish, and the matching [MenuAnalysed].
({Menu menu, MenuAnalysed analysis}) _buildFixture() {
  const dish = Dish(
    id: 'steak',
    name: 'Herb Butter Steak',
    description: '',
    price: 42,
    options: <DishOption>[],
  );
  final menu = Menu(
    venueRef: _ref,
    currency: 'ILS',
    fetchedAt: DateTime.utc(2026),
    categories: const [
      MenuCategory(id: 'c1', name: 'Mains', dishes: [dish]),
    ],
  );
  final analysis = MenuAnalysed(
    dishes: const [
      AnalysedDish(
        dishId: 'steak',
        name: 'Herb Butter Steak',
        verdict: DishVerdict.orderAsIs,
        why: 'Protein and butter, no starch.',
      ),
    ],
    unclassified: const <String>[],
    engine: const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
    analysedAt: DateTime.utc(2026),
  );
  return (menu: menu, analysis: analysis);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Dish note flow', () {
    testWidgets(
      'a note written on a dish shows on its card and survives reopening '
      'the same venue',
      (tester) async {
        // Setup: a repository and classifier scripted to answer the
        // pasted link's venue with one green dish.
        final fixture = _buildFixture();
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, MenuFetched(menu: fixture.menu));
        fakes.classifier.respondWith(fixture.analysis);
        await pumpApp(tester, fakes);

        // Act: paste the link and open the venue.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the dish shows with no note yet.
        expect(find.byType(DishCard), findsOneWidget);
        expect(find.text(_en.dishCardAddNote), findsOneWidget);
        expect(find.text(_note), findsNothing);

        // Act: open the note editor and write a note.
        await tapAndSettle(tester, find.text(_en.dishCardAddNote));
        expect(find.byType(NoteEditorSheet), findsOneWidget);
        // Typed into the sheet's own field: the menu's search field
        // (issue #51) is the first EditableText on screen, under the sheet.
        await tester.enterText(
          find.descendant(
            of: find.byType(NoteEditorSheet),
            matching: find.byType(TextField),
          ),
          _note,
        );
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text(_en.noteEditorSave));

        // Assert: the sheet closed and the card now shows the note.
        expect(find.byType(NoteEditorSheet), findsNothing);
        expect(find.text(_note), findsOneWidget);
        expect(find.text(_en.dishCardAddNote), findsNothing);

        // Act: leave the menu screen and reopen the same venue — a fresh
        // MenuController the way generateRoute builds one per push
        // (app.dart), over the same fakes.notesStore instance.
        await tapAndSettle(tester, find.byTooltip('Back'));
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the note survived the revisit.
        expect(find.byType(DishCard), findsOneWidget);
        expect(find.text(_note), findsOneWidget);
        expect(find.text(_en.dishCardAddNote), findsNothing);
      },
    );

    testWidgets('clearing a note in the editor removes it from the card', (
      tester,
    ) async {
      // Setup
      final fixture = _buildFixture();
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: fixture.menu));
      fakes.classifier.respondWith(fixture.analysis);
      await fakes.notesStore.write(_ref, 'steak', _note);
      await pumpApp(tester, fakes);

      // Act: open the venue and see the note already there.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.text(_en.venueSearchOpen));
      expect(find.text(_note), findsOneWidget);

      // Act: open the editor and clear the note.
      await tapAndSettle(tester, find.text(_note));
      expect(find.byType(NoteEditorSheet), findsOneWidget);
      await tapAndSettle(tester, find.text(_en.noteEditorClear));

      // Assert: the card falls back to the "Add a note" prompt.
      expect(find.byType(NoteEditorSheet), findsNothing);
      expect(find.text(_note), findsNothing);
      expect(find.text(_en.dishCardAddNote), findsOneWidget);
    });
  });
}
