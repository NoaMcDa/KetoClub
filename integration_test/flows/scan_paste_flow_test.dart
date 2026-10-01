// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #83,
// D18): the journey of pasting a menu's text on the Scan tab and seeing it
// classified like any other venue — with no price anywhere.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The pasted menu: two dishes, each with a price the app must never show.
const String _pasted =
    'Herb butter steak 42 ₪\n'
    'Sirloin with fries 45 NIS';

/// The Analyse button on the Scan tab.
Finder get _analyse => find.widgetWithText(FilledButton, _en.scanAnalyse);

/// The verdicts the faked classifier answers with, keyed by the dish ids
/// `TextMenuSource` assigns (`p1`, `p2`).
MenuAnalysed _analysis() => MenuAnalysed(
  dishes: const [
    AnalysedDish(
      dishId: 'p1',
      name: 'Herb butter steak',
      verdict: DishVerdict.orderAsIs,
      why: 'Protein and butter, no starch.',
    ),
    AnalysedDish(
      dishId: 'p2',
      name: 'Sirloin with fries',
      verdict: DishVerdict.modifiable,
      why: 'The steak is keto-safe; the fries are not.',
      modification: 'Ask for a green salad instead of fries.',
    ),
  ],
  unclassified: const <String>[],
  engine: const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
  analysedAt: DateTime.utc(2026),
);

/// Gives the surface a phone-tall viewport, so a lazy `ListView` builds
/// both dish cards (CLAUDE.md's traps); reset when the test ends.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Scan paste flow', () {
    testWidgets(
      'user pastes a menu, taps Analyse and sees verdicts with no price',
      (tester) async {
        // Setup: the real controller, parser and route over in-memory
        // fakes; only the classifier's answer is scripted.
        _useTallSurface(tester);
        final fakes = FakeAppDependencies();
        fakes.classifier.respondWith(_analysis());
        await pumpApp(tester, fakes);

        // Act: open the Scan tab, paste, and analyse.
        await tapAndSettle(tester, navDestination(_en.navScan));
        expect(tester.widget<FilledButton>(_analyse).onPressed, isNull);
        await enterText(tester, _pasted);
        await tapAndSettle(tester, _analyse);

        // Assert: the classified menu is shown, one badge per dish and
        // the engine chip only an analysis brings.
        expect(find.byType(VerdictCounterTiles), findsOneWidget);
        expect(find.byType(EngineChip), findsOneWidget);
        expect(find.byType(DishCard), findsNWidgets(2));
        expect(find.byType(StatusBadge), findsWidgets);
        expect(find.text('Herb butter steak'), findsOneWidget);
        expect(find.text('Sirloin with fries'), findsOneWidget);
        expect(find.text(_en.sourceScanned), findsWidgets);

        // Assert: a scan's price never renders, and never reached the
        // classifier either.
        expect(find.textContaining('₪'), findsNothing);
        expect(find.textContaining('NIS'), findsNothing);
        final asked = fakes.classifier.calls.single;
        expect(asked.venueRef.platformId, isNotEmpty);
        for (final dish in asked.allDishes) {
          expect(dish.name, isNot(contains('₪')));
          expect(dish.name, isNot(contains('NIS')));
        }
      },
    );

    testWidgets('the same text pasted twice opens the same saved entry', (
      tester,
    ) async {
      // Setup
      _useTallSurface(tester);
      final fakes = FakeAppDependencies();
      fakes.classifier.respondWith(_analysis());
      await pumpApp(tester, fakes);
      await tapAndSettle(tester, navDestination(_en.navScan));

      // Act: paste and analyse, go back, paste and analyse once more.
      await enterText(tester, _pasted);
      await tapAndSettle(tester, _analyse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, _analyse);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Assert: Saved holds one pasted menu, not two.
      await tapAndSettle(tester, navDestination(_en.navSaved));
      expect(find.text(_en.sourceScanned), findsWidgets);
      expect(find.text(_en.savedEntryDishCount(2)), findsOneWidget);
      expect(find.textContaining('₪'), findsNothing);
    });
  });
}
