import 'dart:async';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/analysis_progress_row.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/note_editor_sheet.dart';
import 'package:ketoclub/widgets/offline_banner.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_connectivity.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_screen_brightness.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens, unless a test builds its own.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// The English strings a test can read expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the one Locale('he') test.
final AppLocalizations _he = AppLocalizationsHe();

/// A minimal, valid [Dish] named [name].
Dish _dish(String name, {String id = 'd1'}) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A minimal, valid [Menu] for [ref], containing [dishes] under one
/// category.
Menu _menuOf(List<Dish> dishes, {VenueRef ref = _ref, DateTime? fetchedAt}) =>
    Menu(
      venueRef: ref,
      currency: 'ILS',
      fetchedAt: fetchedAt ?? DateTime.utc(2026),
      categories: <MenuCategory>[
        MenuCategory(id: 'c1', name: 'Mains', dishes: dishes),
      ],
    );

/// A verdict for [dish] with [verdict], requiring [modification] only when
/// [verdict] is [DishVerdict.modifiable].
AnalysedDish _verdictFor(
  Dish dish,
  DishVerdict verdict, {
  String? modification,
}) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: verdict,
  why: 'why',
  modification: modification,
);

/// Builds the [MenuController] the widget under test is pumped over.
MenuController _controllerFor({
  required FakeMenuRepository repository,
  FakeMenuClassifier? classifier,
  FakeSettingsStore? settings,
  FakeNotesStore? notes,
}) => MenuController(
  repository,
  classifier ?? FakeMenuClassifier(),
  settings ?? FakeSettingsStore(),
  notes ?? FakeNotesStore(),
);

/// Gives the test surface a phone-tall viewport for the rest of the test.
///
/// The default 800×600 surface fits the header, the verdict tiles, the
/// legend, the search field, the chip row and a category heading with
/// room for only one dish card underneath; a lazy [ListView] then never
/// builds the second card, and every `find` for it comes back empty. The
/// size is reset when the test ends.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps a [MenuScreen] for [ref] over [controller], inside a localised
/// [MaterialApp] with [controller] provided through `provider` — the
/// shape every test in this file uses.
Future<void> _pump(
  WidgetTester tester,
  MenuController controller, {
  VenueRef ref = _ref,
  Locale locale = const Locale('en'),
  ScreenBrightness? screenBrightness,
  Connectivity? connectivity,
  FakeExternalLinkOpener? externalLinkOpener,
}) {
  _useTallSurface(tester);
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: ChangeNotifierProvider<MenuController>.value(
        value: controller,
        // Keyed by ref so that a test pumping a second ref onto the same
        // tree slot (the platform-name loop test) mounts a fresh
        // MenuScreen — and so runs initState's open() again — rather than
        // Flutter updating the previous element in place.
        child: MenuScreen(
          key: ValueKey(ref.cacheKey),
          ref: ref,
          screenBrightness: screenBrightness ?? FakeScreenBrightness(),
          connectivity: connectivity ?? FakeConnectivity(),
          externalLinkOpener: externalLinkOpener ?? FakeExternalLinkOpener(),
        ),
      ),
    ),
  );
}

/// Pumps a [MenuScreen] like [_pump], but with a route table that records
/// every pushed route name into [pushedNames] instead of building it — for
/// tests that tap an app bar action or check where a route push landed,
/// rather than reading the body.
Future<void> _pumpWithRoutes(
  WidgetTester tester,
  MenuController controller,
  List<String> pushedNames, {
  Connectivity? connectivity,
}) {
  _useTallSurface(tester);
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<MenuController>.value(
        value: controller,
        child: MenuScreen(
          ref: _ref,
          screenBrightness: FakeScreenBrightness(),
          connectivity: connectivity ?? FakeConnectivity(),
          externalLinkOpener: FakeExternalLinkOpener(),
        ),
      ),
      onGenerateRoute: (settings) {
        pushedNames.add(settings.name ?? '');
        return MaterialPageRoute<void>(
          builder: (_) => const SizedBox.shrink(),
          settings: settings,
        );
      },
    ),
  );
}

/// Pumps a [MenuScreen] whose classifier announces [announces] and then
/// holds its answer until [gate] completes, and pumps on until the
/// screen shows the menu under a progress row (issue #65).
///
/// Plain `pump`s, never `pumpAndSettle`: the progress row's spinner
/// animates for as long as [gate] is open, so the tree never settles.
Future<void> _pumpWhileClassifying(
  WidgetTester tester, {
  required List<ClassifyingEngine> announces,
  required Future<void> gate,
  Locale locale = const Locale('en'),
}) async {
  final repository = FakeMenuRepository()
    ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
  final classifier = FakeMenuClassifier()
    ..announces = announces
    ..gate = gate;
  final controller = _controllerFor(
    repository: repository,
    classifier: classifier,
  );
  await _pump(tester, controller, locale: locale);
  // The first pump runs the post-frame open() and its microtasks up to
  // the gate; the second renders the frame that state produced.
  await tester.pump();
  await tester.pump();
}

void main() {
  group('MenuScreen', () {
    testWidgets(
      'tapping the settings action pushes the settings route even after a '
      'failed fetch',
      (tester) async {
        // Arrange: the failure whose copy names Settings as the way out
        // must leave Settings reachable from this very screen.
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.blockedByBrowser,
            ),
          );
        final controller = _controllerFor(repository: repository);
        final pushedNames = <String>[];
        await _pumpWithRoutes(tester, controller, pushedNames);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/settings'));
      },
    );

    testWidgets('build shows menuLoading before the fetch resolves', (
      tester,
    ) async {
      // Arrange
      final repository = FakeMenuRepository();
      final controller = _controllerFor(repository: repository);

      // Act: a single pumpWidget renders the first frame, built before the
      // post-frame callback's open() call has had a chance to resolve —
      // the fake repository answers on a microtask, not this frame.
      await _pump(tester, controller);

      // Assert
      expect(find.text(_en.menuLoading), findsOneWidget);
      expect(find.byType(DishCard), findsNothing);
    });

    group('progress while the menu is analysed (issue #65)', () {
      testWidgets(
        'while the AI engine runs the screen says "Asking the AI" above '
        'the unjudged menu',
        (tester) async {
          // Arrange
          final gate = Completer<void>();

          // Act
          await _pumpWhileClassifying(
            tester,
            announces: const [ClassifyingEngine.llm],
            gate: gate.future,
          );

          // Assert: the menu itself is already readable, judged or not.
          expect(find.text(_en.menuProgressAskingAi), findsOneWidget);
          expect(find.text(_en.menuProgressApplyingRules), findsNothing);
          expect(find.byType(DishCard), findsOneWidget);
          expect(find.byType(EngineChip), findsNothing);
          expect(find.byType(VerdictCounterTiles), findsNothing);

          // Cleanup: let the analysis finish so no timer outlives the test.
          gate.complete();
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'while only the rules engine runs the screen says "Applying the '
        'rules"',
        (tester) async {
          // Arrange
          final gate = Completer<void>();

          // Act
          await _pumpWhileClassifying(
            tester,
            announces: const [ClassifyingEngine.rules],
            gate: gate.future,
          );

          // Assert
          expect(find.text(_en.menuProgressApplyingRules), findsOneWidget);
          expect(find.text(_en.menuProgressAskingAi), findsNothing);

          gate.complete();
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'after an AI call falls back the screen names the rules, not the AI',
        (tester) async {
          // Arrange
          final gate = Completer<void>();

          // Act
          await _pumpWhileClassifying(
            tester,
            announces: const [ClassifyingEngine.llm, ClassifyingEngine.rules],
            gate: gate.future,
          );

          // Assert
          expect(find.text(_en.menuProgressApplyingRules), findsOneWidget);
          expect(find.text(_en.menuProgressAskingAi), findsNothing);

          gate.complete();
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'before any engine announces itself the screen says "Analysing the '
        'menu" and names no engine',
        (tester) async {
          // Arrange
          final gate = Completer<void>();

          // Act
          await _pumpWhileClassifying(
            tester,
            announces: const <ClassifyingEngine>[],
            gate: gate.future,
          );

          // Assert
          expect(find.text(_en.menuProgressAnalysing), findsOneWidget);
          expect(find.text(_en.menuProgressAskingAi), findsNothing);
          expect(find.text(_en.menuProgressApplyingRules), findsNothing);

          gate.complete();
          await tester.pumpAndSettle();
        },
      );

      testWidgets('the progress row is gone once the analysis lands', (
        tester,
      ) async {
        // Arrange
        final gate = Completer<void>();
        await _pumpWhileClassifying(
          tester,
          announces: const [ClassifyingEngine.llm],
          gate: gate.future,
        );
        expect(find.text(_en.menuProgressAskingAi), findsOneWidget);

        // Act
        gate.complete();
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.menuProgressAskingAi), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(EngineChip), findsOneWidget);
      });

      testWidgets('the progress copy is Hebrew under the he locale', (
        tester,
      ) async {
        // Arrange
        final gate = Completer<void>();

        // Act
        await _pumpWhileClassifying(
          tester,
          announces: const [ClassifyingEngine.llm],
          gate: gate.future,
          locale: const Locale('he'),
        );

        // Assert
        expect(find.text(_he.menuProgressAskingAi), findsOneWidget);
        expect(find.byType(AnalysisProgressRow), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
      'the header falls back to the pasted reference when venueName is '
      'null — the normal case, not an edge case (Menu.venueName)',
      (tester) async {
        // Arrange: _menuOf never sets venueName, matching every real Wolt
        // fetch today.
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert: falls back to the ref's own platform id, never a
        // placeholder like "Restaurant".
        expect(find.text(_ref.platformId), findsOneWidget);
        expect(find.text('Restaurant'), findsNothing);
      },
    );

    testWidgets('the header shows Menu.venueName when the platform named '
        'the venue', (tester) async {
      // Arrange
      final menu = Menu(
        venueRef: _ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: [
          MenuCategory(id: 'c1', name: 'Mains', dishes: [_dish('Steak')]),
        ],
        venueName: 'Sunny Diner',
      );
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: menu));
      final controller = _controllerFor(repository: repository);

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Sunny Diner'), findsOneWidget);
      expect(find.text(_ref.platformId), findsNothing);
    });

    testWidgets(
      'the source line names the platform and shows for a freshly fetched '
      'menu, not only a cached one',
      (tester) async {
        // Arrange: fetched two minutes ago, not from cache.
        final fetchedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 2),
        );
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            MenuFetched(menu: _menuOf([_dish('Steak')], fetchedAt: fetchedAt)),
          );
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        expect(controller.isFromCache, isFalse);
        expect(
          find.text(_en.menuSourceLine('Wolt', _en.ageMinutes(2))),
          findsOneWidget,
        );
      },
    );

    group('open on platform (issue #53)', () {
      testWidgets(
        'the open-on-platform action appears beside the source line for a '
        'Wolt ref and opens the derived Wolt URL through the external link '
        'opener',
        (tester) async {
          // Arrange
          final repository = FakeMenuRepository()
            ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
          final controller = _controllerFor(repository: repository);
          final opener = FakeExternalLinkOpener();

          // Act
          await _pump(tester, controller, externalLinkOpener: opener);
          await tester.pumpAndSettle();

          // Assert: the action is present, tooltipped with the platform
          // name — the same string a screen reader reads as its label.
          final label = _en.menuOpenOnPlatform('Wolt');
          expect(find.byTooltip(label), findsOneWidget);
          expect(find.byIcon(Icons.open_in_new), findsOneWidget);

          // Act: tap it.
          await tester.tap(find.byIcon(Icons.open_in_new));
          await tester.pumpAndSettle();

          // Assert: opened through the fake opener with the URL
          // VenueRefResolver.platformUrl derives for this ref, never
          // handled inside the app itself.
          expect(
            opener.openCalls,
            equals([VenueRefResolver.platformUrl(_ref)]),
          );
        },
      );

      testWidgets(
        'the open-on-platform action opens the derived 10bis URL for a '
        '10bis ref',
        (tester) async {
          // Arrange
          const ref = VenueRef(source: MenuSource.tenbis, platformId: '999');
          final repository = FakeMenuRepository()
            ..stub(ref, MenuFetched(menu: _menuOf([_dish('Steak')], ref: ref)));
          final controller = _controllerFor(repository: repository);
          final opener = FakeExternalLinkOpener();

          // Act
          await _pump(tester, controller, ref: ref, externalLinkOpener: opener);
          await tester.pumpAndSettle();
          final label = _en.menuOpenOnPlatform('10bis');
          expect(find.byTooltip(label), findsOneWidget);
          await tester.tap(find.byIcon(Icons.open_in_new));
          await tester.pumpAndSettle();

          // Assert
          expect(opener.openCalls, equals([VenueRefResolver.platformUrl(ref)]));
        },
      );

      testWidgets(
        'the open-on-platform action is hidden for a source with no known '
        'URL form (Tabit)',
        (tester) async {
          // Arrange
          const ref = VenueRef(source: MenuSource.tabit, platformId: 't1');
          final repository = FakeMenuRepository()
            ..stub(ref, MenuFetched(menu: _menuOf([_dish('Steak')], ref: ref)));
          final controller = _controllerFor(repository: repository);

          // Act
          await _pump(tester, controller, ref: ref);
          await tester.pumpAndSettle();

          // Assert: no icon and no tooltip for any platform name renders
          // the action.
          expect(find.byIcon(Icons.open_in_new), findsNothing);
          for (final platform in ['Wolt', '10bis', 'Tabit', 'Ontopo']) {
            expect(
              find.byTooltip(_en.menuOpenOnPlatform(platform)),
              findsNothing,
            );
          }
        },
      );
    });

    testWidgets('the source line renders the platform name and age for a 10bis '
        'VenueRef (issue #47)', (tester) async {
      // Arrange: a 10bis venue, fetched five minutes ago.
      const tenBisRef = VenueRef(source: MenuSource.tenbis, platformId: 'r1');
      final fetchedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      final repository = FakeMenuRepository()
        ..stub(
          tenBisRef,
          MenuFetched(
            menu: _menuOf(
              [_dish('Steak')],
              ref: tenBisRef,
              fetchedAt: fetchedAt,
            ),
          ),
        );
      final controller = _controllerFor(repository: repository);

      // Act
      await _pump(tester, controller, ref: tenBisRef);
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(_en.menuSourceLine('10bis', _en.ageMinutes(5))),
        findsOneWidget,
      );
    });

    testWidgets('tapping the refresh action reaches the repository with '
        'forceRefresh: true (issue #47)', (tester) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
      final controller = _controllerFor(repository: repository);
      await _pump(tester, controller);
      await tester.pumpAndSettle();
      final loadCallsBefore = repository.loadCalls.length;

      // Act: tap the refresh action beside the source line, found by its
      // tooltip / semantics label rather than by icon, since the icon is
      // not itself asserted on here.
      await tester.tap(find.byTooltip(_en.actionRefreshMenu));
      await tester.pumpAndSettle();

      // Assert: a second, forced load beyond the one initState's open()
      // already made — the same contract MenuController.refresh itself
      // upholds (issue #49), now reached from the header action too.
      expect(repository.loadCalls.length, greaterThan(loadCallsBefore));
      expect(
        repository.loadCalls.last,
        equals((ref: _ref, forceRefresh: true)),
      );
    });

    testWidgets(
      'the age label updates after a successful refresh (issue #47)',
      (tester) async {
        // Arrange: fetched two minutes ago.
        final firstFetchedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 2),
        );
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            MenuFetched(
              menu: _menuOf([_dish('Steak')], fetchedAt: firstFetchedAt),
            ),
          );
        final controller = _controllerFor(repository: repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();
        expect(
          find.text(_en.menuSourceLine('Wolt', _en.ageMinutes(2))),
          findsOneWidget,
        );

        // Arrange: the refetch this tap triggers returns a fresher
        // fetchedAt — overwriting the single-ref stub the same way the
        // controller-level refresh tests do.
        final secondFetchedAt = DateTime.now().toUtc();
        repository.stub(
          _ref,
          MenuFetched(
            menu: _menuOf([_dish('Steak')], fetchedAt: secondFetchedAt),
          ),
        );

        // Act
        await tester.tap(find.byTooltip(_en.actionRefreshMenu));
        await tester.pumpAndSettle();

        // Assert: the age reads "just now", derived from the fresh
        // MenuController.fetchedAt this screen already rebuilds on — no
        // separate wiring needed for the label to move forward.
        expect(
          find.text(_en.menuSourceLine('Wolt', _en.ageJustNow)),
          findsOneWidget,
        );
        expect(
          find.text(_en.menuSourceLine('Wolt', _en.ageMinutes(2))),
          findsNothing,
        );
      },
    );

    testWidgets(
      'the refresh action carries a semantics label / tooltip in Hebrew '
      'too (issue #47)',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller, locale: const Locale('he'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byTooltip(_he.actionRefreshMenu), findsOneWidget);
      },
    );

    testWidgets(
      'the keto score badge renders no digit when the analysis has not '
      'produced one — never a fallback 0.0',
      (tester) async {
        // Arrange: the fetch succeeds but analysis fails, so
        // ketoScoreOutOfTen is null.
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            const MenuAnalysisFailed(
              reason: MenuAnalysisFailureReason.badResponse,
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert: no score label, and no stray "0.0".
        expect(controller.ketoScoreOutOfTen, isNull);
        expect(find.text(_en.menuKetoScoreLabel.toUpperCase()), findsNothing);
        expect(find.text('0.0'), findsNothing);
      },
    );

    testWidgets('build shows fetchFailureMessage and a retry affordance for a '
        'reason that retries (issue #68)', (tester) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..stub(
          _ref,
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.offline,
            statusCode: 404,
          ),
        );
      final controller = _controllerFor(repository: repository);

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final message = fetchFailureMessage(
        MenuFetchFailureReason.offline,
        _en,
        platform: 'Wolt',
        statusCode: 404,
      );
      expect(find.text(message), findsOneWidget);
      expect(find.text(_en.actionRetry), findsOneWidget);
    });

    testWidgets(
      'every MenuFetchFailureReason renders its own action (issue #68)',
      (tester) async {
        const retryable = <MenuFetchFailureReason>{
          MenuFetchFailureReason.offline,
          MenuFetchFailureReason.backendUnreachable,
        };
        const backToSearch = <MenuFetchFailureReason>{
          MenuFetchFailureReason.notFound,
          MenuFetchFailureReason.platformChanged,
          MenuFetchFailureReason.unsupportedSource,
        };

        for (final reason in MenuFetchFailureReason.values) {
          // Arrange
          final ref = VenueRef(source: MenuSource.wolt, platformId: '$reason');
          final repository = FakeMenuRepository()
            ..stub(ref, MenuFetchFailed(reason: reason, statusCode: 404));
          final controller = _controllerFor(repository: repository);

          // Act
          await _pump(tester, controller, ref: ref);
          await tester.pumpAndSettle();

          // Assert
          if (retryable.contains(reason)) {
            expect(
              find.text(_en.actionRetry),
              findsOneWidget,
              reason: '$reason should offer Retry',
            );
            expect(find.text(_en.actionBackToSearch), findsNothing);
          } else if (backToSearch.contains(reason)) {
            expect(
              find.text(_en.actionBackToSearch),
              findsOneWidget,
              reason: '$reason should offer Back to search',
            );
            expect(find.text(_en.actionRetry), findsNothing);
          } else {
            // blockedByBrowser: no action button at all, only the copy
            // naming the phone app.
            expect(find.text(_en.actionRetry), findsNothing);
            expect(find.text(_en.actionBackToSearch), findsNothing);
          }
        }
      },
    );

    testWidgets(
      'blockedByBrowser shows no action, only the copy pointing at the '
      'phone app (issue #68)',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.blockedByBrowser,
            ),
          );
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.text(
            fetchFailureMessage(
              MenuFetchFailureReason.blockedByBrowser,
              _en,
              platform: 'Wolt',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text(_en.actionRetry), findsNothing);
        expect(find.text(_en.actionBackToSearch), findsNothing);
      },
    );

    testWidgets(
      'tapping Back to search on notFound pops back to the previous route '
      'when there is one (issue #68)',
      (tester) async {
        // Arrange: a MenuScreen pushed on top of a root route, matching
        // how the real app always reaches it (app.dart's own route
        // table) — MenuScreen never sits at the bottom of a stack.
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            const MenuFetchFailed(reason: MenuFetchFailureReason.notFound),
          );
        final controller = _controllerFor(repository: repository);
        final rootKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorKey: rootKey,
            home: const Scaffold(body: Text('root')),
          ),
        );
        rootKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => ChangeNotifierProvider<MenuController>.value(
              value: controller,
              child: MenuScreen(
                ref: _ref,
                screenBrightness: FakeScreenBrightness(),
                connectivity: FakeConnectivity(),
                externalLinkOpener: FakeExternalLinkOpener(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.actionBackToSearch));
        await tester.pumpAndSettle();

        // Assert: back on the root route, MenuScreen gone.
        expect(find.text('root'), findsOneWidget);
        expect(find.byType(MenuScreen), findsNothing);
      },
    );

    testWidgets(
      'tapping Back to search on notFound navigates to "/" when MenuScreen '
      'has no previous route to pop back to (issue #68)',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            const MenuFetchFailed(reason: MenuFetchFailureReason.notFound),
          );
        final controller = _controllerFor(repository: repository);
        final pushedNames = <String>[];
        // No `home`: a MaterialApp with one answers "/" itself without
        // consulting onGenerateRoute, so the replacement would never be
        // recorded here. The app's own router (app.dart) has no `home`
        // either — every route, "/" included, goes through generateRoute.
        // onGenerateInitialRoutes makes MenuScreen the only route on the
        // stack, so there is nothing for Back to search to pop back to.
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            onGenerateInitialRoutes: (_) => [
              MaterialPageRoute<void>(
                builder: (_) => ChangeNotifierProvider<MenuController>.value(
                  value: controller,
                  child: MenuScreen(
                    ref: _ref,
                    screenBrightness: FakeScreenBrightness(),
                    connectivity: FakeConnectivity(),
                    externalLinkOpener: FakeExternalLinkOpener(),
                  ),
                ),
              ),
            ],
            onGenerateRoute: (settings) {
              pushedNames.add(settings.name ?? '');
              return MaterialPageRoute<void>(
                builder: (_) => const Text('root'),
                settings: settings,
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.actionBackToSearch));
        await tester.pumpAndSettle();

        // Assert: "/" was generated, and it replaced this screen.
        expect(pushedNames, contains('/'));
        expect(find.text('root'), findsOneWidget);
        expect(find.byType(MenuScreen), findsNothing);
      },
    );

    testWidgets('build names the platform matching ref.source in the '
        'failure message', (tester) async {
      // Arrange
      const cases = <({VenueRef ref, String name})>[
        (ref: VenueRef(source: MenuSource.wolt, platformId: 'a'), name: 'Wolt'),
        (
          ref: VenueRef(source: MenuSource.tenbis, platformId: 'b'),
          name: '10bis',
        ),
        (
          ref: VenueRef(source: MenuSource.tabit, platformId: 'c'),
          name: 'Tabit',
        ),
        (
          ref: VenueRef(source: MenuSource.ontopo, platformId: 'd'),
          name: 'Ontopo',
        ),
      ];

      for (final testCase in cases) {
        final repository = FakeMenuRepository()
          ..stub(
            testCase.ref,
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.platformChanged,
              statusCode: 500,
            ),
          );
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller, ref: testCase.ref);
        await tester.pumpAndSettle();

        // Assert
        final message = fetchFailureMessage(
          MenuFetchFailureReason.platformChanged,
          _en,
          platform: testCase.name,
          statusCode: 500,
        );
        expect(find.text(message), findsOneWidget);
      }
    });

    testWidgets('build shows the filter the engine chip and a DishCard per '
        'visibleRows on a loaded menu', (tester) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final yellow = _dish('Fries', id: 'yellow');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green, yellow])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(green, DishVerdict.orderAsIs),
              _verdictFor(
                yellow,
                DishVerdict.modifiable,
                modification: 'Ask for a salad instead of fries.',
              ),
            ],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'test-model'),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(VerdictCounterTiles), findsOneWidget);
      expect(find.byType(EngineChip), findsOneWidget);
      expect(find.byType(DishCard), findsNWidgets(2));
    });

    testWidgets('a RulesEngine result shows the RulesReasonBanner with '
        'analysisFailureMessage and a Settings action for consentWithheld '
        '(issue #119)', (tester) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
            unclassified: const <String>[],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.consentWithheld,
            ),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );
      final pushedNames = <String>[];

      // Act
      await _pumpWithRoutes(tester, controller, pushedNames);
      await tester.pumpAndSettle();

      // Assert: the full sentence renders, not only the engine chip's
      // short reason.
      expect(find.byType(RulesReasonBanner), findsOneWidget);
      expect(
        find.text(
          analysisFailureMessage(
            MenuAnalysisFailureReason.consentWithheld,
            _en,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(_en.actionOpenSettings), findsOneWidget);

      // Act: tap the Settings action.
      await tester.tap(find.text(_en.actionOpenSettings));
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames, contains('/settings'));
    });

    testWidgets('an LlmEngine result shows no RulesReasonBanner (issue #119)', (
      tester,
    ) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'test-model'),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert: EngineChip still shows the AI result, but the sentence
      // banner is only for a rules result.
      expect(find.byType(EngineChip), findsOneWidget);
      for (final reason in MenuAnalysisFailureReason.values) {
        expect(find.text(analysisFailureMessage(reason, _en)), findsNothing);
      }
    });

    testWidgets(
      'tapping the RulesReasonBanner Retry action re-runs the classifier '
      'without refetching the menu (issue #68)',
      (tester) async {
        // Arrange
        final green = _dish('Steak', id: 'green');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([green])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.timeout,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();
        final loadCallsBefore = repository.loadCalls.length;
        final classifyCallsBefore = classifier.calls.length;

        // Act
        await tester.tap(find.text(_en.actionRetry));
        await tester.pumpAndSettle();

        // Assert: reclassified, but no new fetch.
        expect(repository.loadCalls.length, equals(loadCallsBefore));
        expect(classifier.calls.length, greaterThan(classifyCallsBefore));
      },
    );

    testWidgets(
      'the RulesReasonBanner offers no Retry action for notConfigured '
      '(issue #68)',
      (tester) async {
        // Arrange
        final green = _dish('Steak', id: 'green');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([green])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.actionRetry), findsNothing);
      },
    );

    testWidgets(
      'build shows the offline banner while Connectivity reports offline '
      '(issue #68)',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(
          tester,
          controller,
          connectivity: FakeConnectivity(online: false),
        );
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(OfflineBanner), findsOneWidget);
        expect(find.text(_en.offlineBannerMessage), findsOneWidget);
      },
    );

    testWidgets(
      'build shows no offline banner while Connectivity reports online '
      '(issue #68)',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller, connectivity: FakeConnectivity());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.offlineBannerMessage), findsNothing);
      },
    );

    testWidgets('the offline banner clears once a retry finds the device back '
        'online (issue #68)', (tester) async {
      // Arrange: offline at first, so the fetch fails and the banner
      // shows; the fake flips to online before the retry.
      final fakeConnectivity = FakeConnectivity(online: false);
      final repository = FakeMenuRepository()
        ..stub(
          _ref,
          const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
        );
      final controller = _controllerFor(repository: repository);
      await _pump(tester, controller, connectivity: fakeConnectivity);
      await tester.pumpAndSettle();
      expect(find.text(_en.offlineBannerMessage), findsOneWidget);

      // Act: back online, then retry.
      fakeConnectivity.online = true;
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
      await tester.tap(find.text(_en.actionRetry));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.offlineBannerMessage), findsNothing);
      expect(find.text('Steak'), findsOneWidget);
    });

    testWidgets(
      'the legend states the net-carb limit the analysis was made under '
      '(issue #57), not a fixed 6g',
      (tester) async {
        // Arrange: an analysis recorded under a 9 g limit.
        final green = _dish('Steak', id: 'green');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([green])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
              unclassified: const <String>[],
              engine: const LlmEngine(model: 'served-model'),
              analysedAt: DateTime.utc(2026),
              options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 9),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.legendToggle));
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.textContaining(
            'net carbohydrates 9g or less',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'net carbohydrates 6g or less',
            findRichText: true,
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'tapping the legend toggle shows the same three verdict definitions '
      'the system prompt sends (issue #17), and hides them again',
      (tester) async {
        // Arrange
        final green = _dish('Steak', id: 'green');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([green])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert: collapsed by default.
        expect(find.text(_en.legendToggle), findsOneWidget);
        expect(
          find.textContaining(_en.verdictOrderAsIs, findRichText: true),
          findsNothing,
        );

        // Act
        await tester.tap(find.text(_en.legendToggle));
        await tester.pumpAndSettle();

        // Assert: the definitions come from promptVerdictDefinitionsFor
        // itself, not a re-typed copy.
        expect(find.text(_en.legendHide), findsOneWidget);
        expect(
          find.textContaining(_en.verdictOrderAsIs, findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'net carbohydrates 6g or less',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(find.text(_en.legendNote), findsOneWidget);

        // Act: collapse again.
        await tester.tap(find.text(_en.legendHide));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.legendToggle), findsOneWidget);
        expect(
          find.textContaining(
            'net carbohydrates 6g or less',
            findRichText: true,
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'build still shows the raw menu with analysisFailureMessage above it '
      'when analysis fails',
      (tester) async {
        // Arrange
        final steak = _dish('Steak');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([steak])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            const MenuAnalysisFailed(
              reason: MenuAnalysisFailureReason.badResponse,
              detail: 'bad json',
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        final message = analysisFailureMessage(
          MenuAnalysisFailureReason.badResponse,
          _en,
          detail: 'bad json',
        );
        expect(find.text(message), findsOneWidget);
        expect(find.text('Steak'), findsOneWidget);
        expect(find.byType(EngineChip), findsNothing);
        expect(find.byType(VerdictCounterTiles), findsNothing);
      },
    );

    testWidgets(
      'build composes the cachedFrom line and the analysisFailureMessage '
      'line when both apply',
      (tester) async {
        // Arrange
        final fetchedAt = DateTime.utc(2025, 12, 1, 8);
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            MenuFetched(
              menu: _menuOf([_dish('Steak')], fetchedAt: fetchedAt),
              fromCache: true,
              staleReason: MenuFetchFailureReason.offline,
            ),
          );
        final classifier = FakeMenuClassifier()
          ..respondWith(
            const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.timeout),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.text(
            analysisFailureMessage(MenuAnalysisFailureReason.timeout, _en),
          ),
          findsOneWidget,
        );
        expect(
          find.text(fetchFailureMessage(MenuFetchFailureReason.offline, _en)),
          findsOneWidget,
        );
        final formatted = DateFormat.yMMMd('en')
            .add_Hm()
            .format(fetchedAt.toLocal());
        expect(find.text(_en.cachedFrom(formatted)), findsOneWidget);
      },
    );

    testWidgets('build shows menuEmpty for a menu with no dishes', (
      tester,
    ) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf(const <Dish>[])));
      final controller = _controllerFor(repository: repository);

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.menuEmpty), findsOneWidget);
    });

    testWidgets(
      'tapping the Skip tile filters to red dishes only; tapping it again '
      'returns to all — issue #29 replaces the old always-shown collapsed '
      'red group with this tile',
      (tester) async {
        // Arrange
        final green = _dish('Steak', id: 'green');
        final red = _dish('Spaghetti Carbonara', id: 'red');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([green, red])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [
                _verdictFor(green, DishVerdict.orderAsIs),
                _verdictFor(red, DishVerdict.nonKeto),
              ],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert: the default filter (all) shows every dish, red included.
        expect(find.text('Steak'), findsOneWidget);
        expect(find.text('Spaghetti Carbonara'), findsOneWidget);
        expect(find.text(_en.tileRedLabel.toUpperCase()), findsOneWidget);

        // Act: tap the Skip tile.
        await tester.tap(find.text(_en.tileRedLabel.toUpperCase()));
        await tester.pumpAndSettle();

        // Assert: only the red dish shows, and the label says so.
        expect(find.text('Spaghetti Carbonara'), findsOneWidget);
        expect(find.text('Steak'), findsNothing);
        expect(find.text(_en.menuShowingRed), findsOneWidget);

        // Act: tap the now-active Skip tile again.
        await tester.tap(find.text(_en.tileRedLabel.toUpperCase()));
        await tester.pumpAndSettle();

        // Assert: back to showing everything.
        expect(find.text('Steak'), findsOneWidget);
        expect(find.text('Spaghetti Carbonara'), findsOneWidget);
        expect(find.text(_en.menuShowingAll(2)), findsOneWidget);
      },
    );

    testWidgets('the unclassified section renders its names', (tester) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
            unclassified: const <String>['Mystery bowl'],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.unclassifiedTitle(1)), findsOneWidget);
      expect(find.text(_en.unclassifiedExplain), findsOneWidget);
      expect(find.text('Mystery bowl'), findsOneWidget);
    });

    testWidgets('switching the filter changes which cards are visible', (
      tester,
    ) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final yellow = _dish('Fries', id: 'yellow');
      final red = _dish('Pasta', id: 'red');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green, yellow, red])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(green, DishVerdict.orderAsIs),
              _verdictFor(yellow, DishVerdict.modifiable, modification: 'x'),
              _verdictFor(red, DishVerdict.nonKeto),
            ],
            unclassified: const <String>[],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act: tap the Order-as-is tile. Scoped to VerdictCounterTiles: its
      // label text is identical to the green DishCard's own StatusBadge
      // pill ("Order as-is"), so an unscoped find.text would be ambiguous.
      await tester.tap(
        find.descendant(
          of: find.byType(VerdictCounterTiles),
          matching: find.text(_en.tileGreenLabel.toUpperCase()),
        ),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(DishCard), findsOneWidget);
      expect(find.text('Steak'), findsOneWidget);
      expect(find.text(_en.menuShowingGreen), findsOneWidget);
    });

    testWidgets(
      'tapping the yellow tile filters to modifiable dishes only — the '
      "acceptance criterion's paste-link-then-filter-to-yellow flow, at "
      'widget level',
      (tester) async {
        // Arrange
        final green = _dish('Steak', id: 'green');
        final yellow = _dish('Fries', id: 'yellow');
        final red = _dish('Pasta', id: 'red');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([green, yellow, red])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [
                _verdictFor(green, DishVerdict.orderAsIs),
                _verdictFor(yellow, DishVerdict.modifiable, modification: 'x'),
                _verdictFor(red, DishVerdict.nonKeto),
              ],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.tileYellowLabel.toUpperCase()));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(DishCard), findsOneWidget);
        expect(find.text('Fries'), findsOneWidget);
        expect(find.text('Steak'), findsNothing);
        expect(find.text('Pasta'), findsNothing);
        expect(find.text(_en.menuShowingYellow), findsOneWidget);
      },
    );

    testWidgets(
      'tapping a yellow card opens the Waiter Card and the script text is '
      'present',
      (tester) async {
        // Arrange
        const script = 'Ask for a salad instead of fries.';
        final yellow = _dish('Fries', id: 'yellow');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([yellow])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [
                _verdictFor(
                  yellow,
                  DishVerdict.modifiable,
                  modification: script,
                ),
              ],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.waiterCardOpen));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(WaiterCardSheet), findsOneWidget);
        expect(find.text(_en.waiterCardTitle), findsOneWidget);
        expect(find.text(script), findsWidgets);
      },
    );

    testWidgets(
      'opening the waiter card raises the screen brightness and restores '
      'it on close: MenuScreen passes its ScreenBrightness down, so the '
      'sheet is not left with the no-op default (issue #31)',
      (tester) async {
        // Arrange
        const script = 'Ask for a salad instead of fries.';
        final yellow = _dish('Fries', id: 'yellow');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([yellow])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [
                _verdictFor(
                  yellow,
                  DishVerdict.modifiable,
                  modification: script,
                ),
              ],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        final brightness = FakeScreenBrightness();
        await _pump(tester, controller, screenBrightness: brightness);
        await tester.pumpAndSettle();
        expect(brightness.raiseCount, 0);

        // Act
        await tester.tap(find.text(_en.waiterCardOpen));
        await tester.pumpAndSettle();

        // Assert
        expect(brightness.raiseCount, 1);
        expect(brightness.restoreCount, 0);

        // Act again: dismissing the sheet must restore it.
        Navigator.of(tester.element(find.byType(WaiterCardSheet))).pop();
        await tester.pumpAndSettle();

        // Assert
        expect(brightness.restoreCount, 1);
      },
    );

    testWidgets('build renders Hebrew copy under the he locale', (
      tester,
    ) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final red = _dish('Pasta', id: 'red');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green, red])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(green, DishVerdict.orderAsIs),
              _verdictFor(red, DishVerdict.nonKeto),
            ],
            unclassified: const <String>[],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );

      // Act
      await _pump(tester, controller, locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.tileGreenLabel.toUpperCase()), findsOneWidget);
      expect(find.text(_he.tileRedLabel.toUpperCase()), findsOneWidget);
      expect(find.text(_he.menuKetoScoreLabel.toUpperCase()), findsOneWidget);
    });

    testWidgets(
      'pulling the loaded menu down triggers a RefreshIndicator that calls '
      'MenuController.refresh (issue #49)',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final controller = _controllerFor(repository: repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();
        final loadCallsBefore = repository.loadCalls.length;

        // Act: drag the list down far and fast enough to cross
        // RefreshIndicator's trigger threshold.
        // RefreshIndicator arms once the overscroll passes a sixth of the
        // viewport, which is ~260 px on the tall test surface _pump sets.
        await tester.fling(find.byType(ListView), const Offset(0, 600), 1000);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Assert: a second, forced load — MenuController.refresh's own
        // contract — beyond the one initState's open() already made.
        expect(repository.loadCalls.length, greaterThan(loadCallsBefore));
        expect(
          repository.loadCalls.last,
          equals((ref: _ref, forceRefresh: true)),
        );
      },
    );

    testWidgets(
      'pulling to refresh is not disabled by the active filter (issue #49)',
      (tester) async {
        // Arrange: filter narrowed to a verdict with no matching dish, so
        // visibleRows is empty, but the RefreshIndicator must still work.
        final green = _dish('Steak', id: 'green');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([green])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();
        await controller.setFilter(MenuFilter.redOnly);
        await tester.pumpAndSettle();
        expect(find.byType(DishCard), findsNothing);
        final loadCallsBefore = repository.loadCalls.length;

        // Act
        // RefreshIndicator arms once the overscroll passes a sixth of the
        // viewport, which is ~260 px on the tall test surface _pump sets.
        await tester.fling(find.byType(ListView), const Offset(0, 600), 1000);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Assert
        expect(repository.loadCalls.length, greaterThan(loadCallsBefore));
      },
    );

    testWidgets(
      'retry after a failed fetch calls open again with forceRefresh true',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
          );
        final controller = _controllerFor(repository: repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.actionRetry));
        await tester.pumpAndSettle();

        // Assert
        expect(
          repository.loadCalls,
          equals([
            (ref: _ref, forceRefresh: false),
            (ref: _ref, forceRefresh: true),
          ]),
        );
      },
    );

    group('personal notes (issue #52)', () {
      testWidgets('a dish with no note shows the "Add a note" prompt', (
        tester,
      ) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.dishCardAddNote), findsOneWidget);
      });

      testWidgets(
        'a dish with a stored note shows it on the card, not the prompt',
        (tester) async {
          // Arrange
          final repository = FakeMenuRepository()
            ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
          final notes = FakeNotesStore();
          await notes.write(_ref, 'd1', 'Ask for no cheese.');
          final controller = _controllerFor(
            repository: repository,
            notes: notes,
          );

          // Act
          await _pump(tester, controller);
          await tester.pumpAndSettle();

          // Assert
          expect(find.text('Ask for no cheese.'), findsOneWidget);
          expect(find.text(_en.dishCardAddNote), findsNothing);
        },
      );

      testWidgets(
        'tapping the note prompt opens the note editor, and saving shows '
        'the note on the card afterwards',
        (tester) async {
          // Arrange
          final repository = FakeMenuRepository()
            ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
          final controller = _controllerFor(repository: repository);
          await _pump(tester, controller);
          await tester.pumpAndSettle();

          // Act: open the editor.
          await tester.tap(find.text(_en.dishCardAddNote));
          await tester.pumpAndSettle();

          // Assert: the sheet is open.
          expect(find.byType(NoteEditorSheet), findsOneWidget);

          // Act: type a note and save.
          // Scoped to the sheet: the menu's search field (issue #51) is a
          // TextField too, and it is still in the tree under the sheet.
          await tester.enterText(
            find.descendant(
              of: find.byType(NoteEditorSheet),
              matching: find.byType(TextField),
            ),
            'Waitstaff happily substituted cauliflower.',
          );
          await tester.tap(find.text(_en.noteEditorSave));
          await tester.pumpAndSettle();

          // Assert: the sheet closed and the card now shows the note.
          expect(find.byType(NoteEditorSheet), findsNothing);
          expect(
            find.text('Waitstaff happily substituted cauliflower.'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'clearing an existing note in the editor removes it from the card',
        (tester) async {
          // Arrange
          final repository = FakeMenuRepository()
            ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
          final notes = FakeNotesStore();
          await notes.write(_ref, 'd1', 'Ask for no cheese.');
          final controller = _controllerFor(
            repository: repository,
            notes: notes,
          );
          await _pump(tester, controller);
          await tester.pumpAndSettle();

          // Act: open the editor and clear.
          await tester.tap(find.text('Ask for no cheese.'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(_en.noteEditorClear));
          await tester.pumpAndSettle();

          // Assert
          expect(find.byType(NoteEditorSheet), findsNothing);
          expect(find.text('Ask for no cheese.'), findsNothing);
          expect(find.text(_en.dishCardAddNote), findsOneWidget);
        },
      );

      testWidgets(
        'a note is shown for a non-keto dish too, not only a modifiable '
        'one',
        (tester) async {
          // Arrange
          final red = _dish('Pasta', id: 'red');
          final repository = FakeMenuRepository()
            ..stub(_ref, MenuFetched(menu: _menuOf([red])));
          final classifier = FakeMenuClassifier()
            ..respondWith(
              MenuAnalysed(
                dishes: [_verdictFor(red, DishVerdict.nonKeto)],
                unclassified: const <String>[],
                engine: const RulesEngine(
                  reason: MenuAnalysisFailureReason.notConfigured,
                ),
                analysedAt: DateTime.utc(2026),
              ),
            );
          final notes = FakeNotesStore();
          await notes.write(_ref, 'red', 'Skip it.');
          final controller = _controllerFor(
            repository: repository,
            classifier: classifier,
            notes: notes,
          );

          // Act
          await _pump(tester, controller);
          await tester.pumpAndSettle();

          // Assert
          expect(find.text('Skip it.'), findsOneWidget);
        },
      );
    });

    group('search and category jump (issue #51)', () {
      testWidgets('typing in the search field narrows the dish cards', (
        tester,
      ) async {
        // Arrange
        final steak = _dish('Grilled Steak', id: 'steak');
        final salad = _dish('Greek Salad', id: 'salad');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([steak, salad])));
        final controller = _controllerFor(repository: repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();
        expect(find.byType(DishCard), findsNWidgets(2));

        // Act
        await tester.enterText(find.byType(TextField), 'steak');
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(DishCard), findsOneWidget);
        expect(find.text('Grilled Steak'), findsOneWidget);
        expect(find.text('Greek Salad'), findsNothing);
      });

      testWidgets(
        'a search with no matching dish shows menuNoResults instead of an '
        'empty list',
        (tester) async {
          // Arrange
          final repository = FakeMenuRepository()
            ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
          final controller = _controllerFor(repository: repository);
          await _pump(tester, controller);
          await tester.pumpAndSettle();

          // Act
          await tester.enterText(find.byType(TextField), 'sushi');
          await tester.pumpAndSettle();

          // Assert
          expect(find.byType(DishCard), findsNothing);
          expect(find.text(_en.menuNoResults), findsOneWidget);
        },
      );

      testWidgets(
        'clearing the search field with its clear button restores every '
        'dish card',
        (tester) async {
          // Arrange
          final steak = _dish('Grilled Steak', id: 'steak');
          final salad = _dish('Greek Salad', id: 'salad');
          final repository = FakeMenuRepository()
            ..stub(_ref, MenuFetched(menu: _menuOf([steak, salad])));
          final controller = _controllerFor(repository: repository);
          await _pump(tester, controller);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'steak');
          await tester.pumpAndSettle();
          expect(find.byType(DishCard), findsOneWidget);

          // Act
          await tester.tap(find.byIcon(Icons.clear));
          await tester.pumpAndSettle();

          // Assert
          expect(find.byType(DishCard), findsNWidgets(2));
        },
      );

      testWidgets(
        "tapping a category chip brings that category's header on screen "
        '— it is not there before the tap, since a ListView is lazy and '
        'this menu is long enough to keep it off the built range',
        (tester) async {
          // Arrange: eight categories of five dishes each — long enough
          // that the last category's header is not yet in the element
          // tree when the screen first settles.
          final categories = <MenuCategory>[
            for (var c = 0; c < 8; c++)
              MenuCategory(
                id: 'cat$c',
                name: 'Category $c',
                dishes: [
                  for (var d = 0; d < 5; d++) _dish('Dish $c-$d', id: 'd$c-$d'),
                ],
              ),
          ];
          final menu = Menu(
            venueRef: _ref,
            currency: 'ILS',
            fetchedAt: DateTime.utc(2026),
            categories: categories,
          );
          final repository = FakeMenuRepository()
            ..stub(_ref, MenuFetched(menu: menu));
          final controller = _controllerFor(repository: repository);
          await _pump(tester, controller);
          await tester.pumpAndSettle();

          // Assert: only the chip carries this label so far — the header
          // for the same category, far down the list, has not been built.
          expect(find.text('Category 7'), findsOneWidget);

          // Act: the eighth chip sits past the right edge of the chip
          // row, so scroll it into view first — a tap on an off-screen
          // widget lands on nothing.
          await tester.ensureVisible(find.text('Category 7'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Category 7'));
          await tester.pumpAndSettle();

          // Assert: the header (the styled Text; the chip's label has no
          // style of its own) is now built and on screen.
          final header = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == 'Category 7' &&
                widget.style != null,
            description: "the 'Category 7' heading",
          );
          expect(header, findsOneWidget);
          final headerRect = tester.getRect(header);
          final screen = tester.getRect(find.byType(MenuScreen));
          expect(screen.overlaps(headerRect), isTrue);
        },
      );
    });
  });
}
