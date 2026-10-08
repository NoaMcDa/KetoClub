import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/saved_screen.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/state/saved_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_visit_history_store.dart';

/// The English strings a test can read expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

const VenueRef _woltRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'vitrina-lilinblum',
);

/// A minimal, valid [Menu] for [ref] fetched at [fetchedAt], with [dishes]
/// dishes and [venueName].
Menu _menuWith(
  VenueRef ref,
  DateTime fetchedAt, {
  int dishes = 1,
  String? venueName,
}) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: fetchedAt,
  venueName: venueName,
  categories: [
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: [
        for (var i = 0; i < dishes; i++)
          Dish(
            id: 'd$i',
            name: 'Dish $i',
            description: '',
            price: 10,
            options: const [],
          ),
      ],
    ),
  ],
);

/// A [MenuAnalysed] placing one green, one yellow and one red dish, which
/// scores `(1 + 0.5) / 3 * 10 = 5.0`.
MenuAnalysed _mixedAnalysis() => MenuAnalysed(
  dishes: const <AnalysedDish>[
    AnalysedDish(
      dishId: 'd0',
      name: 'Dish 0',
      verdict: DishVerdict.orderAsIs,
      why: 'No starch.',
    ),
    AnalysedDish(
      dishId: 'd1',
      name: 'Dish 1',
      verdict: DishVerdict.modifiable,
      why: 'Has a side.',
      modification: 'Swap the side.',
    ),
    AnalysedDish(
      dishId: 'd2',
      name: 'Dish 2',
      verdict: DishVerdict.nonKeto,
      why: 'Pasta.',
    ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'test/model'),
  analysedAt: DateTime.utc(2026),
);

/// A Recent list's stores and its controller: a fake cache and a fake
/// visit history, seeded through [open] and [visit].
final class _Harness {
  /// The cached menus.
  final FakeMenuRepository repository = FakeMenuRepository();

  /// The menus opened on this device.
  final FakeVisitHistoryStore history = FakeVisitHistoryStore(
    FakeClock(DateTime.utc(2026)),
  );

  /// The controller under the screen, over [repository] and [history].
  late final SavedController controller = SavedController(repository, history);

  /// Caches [cached] and records a visit to it — the state opening a menu
  /// leaves behind — last opened at [openedAt] (default: when the menu
  /// was fetched), under [name] and in [city].
  void open(
    CachedMenu cached, {
    DateTime? openedAt,
    String? name,
    String? city,
    int openCount = 1,
  }) {
    repository.seedCache(cached);
    visit(
      cached.menu.venueRef,
      openedAt: openedAt ?? cached.menu.fetchedAt,
      name: name,
      city: city,
      openCount: openCount,
    );
  }

  /// Records a visit to [ref] only, with no cached copy unless [open] or
  /// the repository adds one; [openedAt] defaults to now.
  void visit(
    VenueRef ref, {
    DateTime? openedAt,
    String? name,
    String? city,
    int openCount = 1,
    int? dishCount,
    double? score,
    int? greenCount,
    int? yellowCount,
  }) {
    final at = openedAt ?? DateTime.now();
    history.seed(
      VisitEntry(
        ref: ref,
        name: name,
        city: city,
        firstOpenedAt: at,
        lastOpenedAt: at,
        openCount: openCount,
        dishCount: dishCount,
        score: score,
        greenCount: greenCount,
        yellowCount: yellowCount,
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  SavedController controller, {
  Locale locale = const Locale('en'),
  ValueChanged<String>? onNavigate,
  ValueChanged<Object?>? onNavigateArguments,
  ThemeData? theme,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      navigatorObservers: navigatorObservers,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) {
          if (settings.name != '/') {
            onNavigate?.call(settings.name!);
            onNavigateArguments?.call(settings.arguments);
          }
          return settings.name == '/'
              ? ChangeNotifierProvider<SavedController>.value(
                  value: controller,
                  child: const SavedScreen(),
                )
              : Text('pushed:${settings.name}');
        },
      ),
    ),
  );
}

/// A [NavigatorObserver] recording the name of every route a
/// [Navigator.pushReplacementNamed] call replaces the current one with
/// (issue #63) — the shape `AppShell`'s own tab switch uses, and the way
/// [SavedScreen]'s "Find a restaurant" action switches to Explore.
final class _ReplaceRecordingObserver extends NavigatorObserver {
  /// Every replacement route's name, in call order.
  final List<String?> replacedWith = <String?>[];

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacedWith.add(newRoute?.settings.name);
  }
}

void main() {
  group('SavedScreen', () {
    testWidgets('a pasted menu is titled and labelled Pasted menu, never by '
        'its hash (issue #83)', (tester) async {
      // Arrange
      const scanRef = VenueRef(source: MenuSource.scan, platformId: '0badf00d');
      final h = _Harness()
        ..open(CachedMenu(menu: _menuWith(scanRef, DateTime.now().toUtc())));
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert: the title, and the "{platform} · {age}" line.
      expect(find.text(_en.sourceScanned), findsOneWidget);
      expect(find.textContaining('${_en.sourceScanned} · '), findsOneWidget);
      expect(find.text('0badf00d'), findsNothing);
    });

    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets(
        'shows three SavedEntrySkeletons under the ${entry.key} theme '
        'while the initial load is in flight (issue #63)',
        (tester) async {
          // Arrange: hold savedMenus() open so the transient isLoading
          // state stays on screen long enough to assert against.
          final gate = Completer<void>();
          final repository = FakeMenuRepository()..savedMenusGate = gate.future;
          final controller = SavedController(repository);

          // Act
          await _pump(tester, controller, theme: entry.value);
          await tester.pump();

          // Assert: the skeletons stand in for a spinner, announced once
          // through a Semantics label.
          expect(find.byType(SavedEntrySkeleton), findsNWidgets(3));
          expect(find.bySemanticsLabel(_en.savedLoading), findsOneWidget);

          // Cleanup: release the gate so no timer/future is left pending.
          gate.complete();
          await tester.pumpAndSettle();
        },
      );
    }

    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets(
        'shows the reworked empty state and a Find a restaurant action '
        'under the ${entry.key} theme when nothing is cached (issue #63)',
        (tester) async {
          // Arrange
          final controller = SavedController(FakeMenuRepository());

          // Act
          await _pump(tester, controller, theme: entry.value);
          await tester.pumpAndSettle();

          // Assert
          expect(find.text(_en.savedPlaceholderTitle), findsOneWidget);
          expect(find.text(_en.savedPlaceholderBody), findsOneWidget);
          expect(find.text(_en.venueSearchLabel), findsOneWidget);
        },
      );
    }

    testWidgets(
      "tapping the empty state's Find a restaurant action switches to "
      "the Explore tab — a pushReplacementNamed('/'), the same route "
      "AppShell's own tab tap uses (issue #63)",
      (tester) async {
        // Arrange
        final controller = SavedController(FakeMenuRepository());
        final observer = _ReplaceRecordingObserver();
        await _pump(tester, controller, navigatorObservers: [observer]);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.venueSearchLabel));
        await tester.pumpAndSettle();

        // Assert
        expect(observer.replacedWith, ['/']);
      },
    );

    testWidgets('lists a cached menu with its venue name, source line and '
        'dish count', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(
              _woltRef,
              DateTime.now(),
              dishes: 3,
              venueName: 'Vitrina',
            ),
          ),
        );
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Vitrina'), findsOneWidget);
      expect(find.textContaining('Wolt'), findsOneWidget);
      expect(find.text(_en.savedEntryDishCount(3)), findsOneWidget);
      expect(find.byType(EngineChip), findsNothing);
    });

    testWidgets('falls back to the platformId when venueName is null', (
      tester,
    ) async {
      // Arrange
      final h = _Harness()
        ..open(CachedMenu(menu: _menuWith(_woltRef, DateTime.now())));
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_woltRef.platformId), findsOneWidget);
    });

    testWidgets('shows an EngineChip for an analysed entry', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(_woltRef, DateTime.now()),
            analysis: MenuAnalysed(
              dishes: const <AnalysedDish>[],
              unclassified: const <String>[],
              engine: const LlmEngine(model: 'test/model'),
              analysedAt: DateTime.utc(2026),
            ),
          ),
        );
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(EngineChip), findsOneWidget);
      // No dish was placed, so there is no score to claim (never 0.0).
      expect(find.byType(KetoScoreBadge), findsNothing);
      expect(find.text(_en.venueCardGreenCount(0)), findsNothing);
    });

    testWidgets('shows the keto score and the green and yellow counts of an '
        'analysed entry', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(_woltRef, DateTime.now(), dishes: 3),
            analysis: _mixedAnalysis(),
          ),
        );
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(KetoScoreBadge), findsOneWidget);
      expect(find.text('5.0'), findsOneWidget);
      expect(find.text(_en.venueCardGreenCount(1)), findsOneWidget);
      expect(find.text(_en.venueCardYellowCount(1)), findsOneWidget);
    });

    testWidgets('shows no score for an entry that was never analysed', (
      tester,
    ) async {
      // Arrange
      final h = _Harness()
        ..open(CachedMenu(menu: _menuWith(_woltRef, DateTime.now())));
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(KetoScoreBadge), findsNothing);
      expect(find.text(_en.venueCardYellowCount(0)), findsNothing);
    });

    testWidgets('lists the most recently opened menu first, whenever it '
        'was fetched (issue #313)', (tester) async {
      // Arrange: the older visit's menu was fetched later.
      const olderRef = VenueRef(source: MenuSource.wolt, platformId: 'older');
      const newerRef = VenueRef(source: MenuSource.wolt, platformId: 'newer');
      final now = DateTime.now();
      final h = _Harness()
        ..open(
          CachedMenu(menu: _menuWith(olderRef, now, venueName: 'Older Place')),
          openedAt: now.subtract(const Duration(hours: 3)),
        )
        ..open(
          CachedMenu(
            menu: _menuWith(
              newerRef,
              now.subtract(const Duration(hours: 5)),
              venueName: 'Newer Place',
            ),
          ),
          openedAt: now.subtract(const Duration(hours: 1)),
        );
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final newerTop = tester.getTopLeft(find.text('Newer Place'));
      final olderTop = tester.getTopLeft(find.text('Older Place'));
      expect(newerTop.dy, lessThan(olderTop.dy));
    });

    testWidgets(
      'tapping an entry navigates to its venue route and forwards the '
      'cached venue name as arguments (issue #169)',
      (tester) async {
        // Arrange
        final h = _Harness()
          ..open(
            CachedMenu(
              menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
            ),
          );
        final controller = h.controller;
        String? navigated;
        Object? forwardedArgs;

        // Act
        await _pump(
          tester,
          controller,
          onNavigate: (name) => navigated = name,
          onNavigateArguments: (args) => forwardedArgs = args,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vitrina'));
        await tester.pumpAndSettle();

        // Assert
        expect(
          navigated,
          '/venue/${_woltRef.source.name}/${_woltRef.platformId}',
        );
        expect(find.text('pushed:$navigated'), findsOneWidget);
        // Issue #169: the cached venue name rides along in the route's
        // VenueOpenHint (issue #307), so the menu header can show it
        // instead of the slug.
        expect(forwardedArgs, const VenueOpenHint(name: 'Vitrina'));
      },
    );

    testWidgets('removing via the trailing action hides the row, shows an '
        'undo SnackBar, and undo restores it without touching the '
        'repository', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
          ),
        );
      final controller = h.controller;
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act: remove. Two pumps: the first applies the synchronous
      // hide() rebuild and starts the SnackBar's enter animation, the
      // second lets that animation finish so its text is on screen.
      await tester.tap(find.byTooltip(_en.savedRemove));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert: hidden immediately, undo offered.
      expect(find.text('Vitrina'), findsNothing);
      expect(find.text(_en.savedRemovedMessage('Vitrina')), findsOneWidget);
      expect(find.text(_en.savedUndo), findsOneWidget);

      // Act: undo.
      await tester.tap(find.text(_en.savedUndo));
      await tester.pumpAndSettle();

      // Assert: restored, and neither store was ever asked to delete.
      expect(find.text('Vitrina'), findsOneWidget);
      expect(h.repository.removedRefs, isEmpty);
      expect(h.history.removedRefs, isEmpty);
    });

    testWidgets(
      'letting the undo SnackBar close without tapping undo deletes from '
      'the repository',
      (tester) async {
        // Arrange
        final h = _Harness()
          ..open(
            CachedMenu(
              menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
            ),
          );
        final controller = h.controller;
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.byTooltip(_en.savedRemove));
        // The SnackBar's auto-dismiss timer starts only once its entrance
        // animation completes, so settle that first, then advance the fake
        // clock past the timer, then settle the exit animation so `closed`
        // completes and the removal is committed. The screen passes
        // `persist: false`, because a SnackBar with an action would
        // otherwise never time out.
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Assert
        expect(h.repository.removedRefs, [_woltRef]);
        expect(h.history.removedRefs, [_woltRef]);
      },
    );

    testWidgets('an empty list shown after removing the only entry reads '
        'as the empty state', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
          ),
        );
      final controller = h.controller;
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.byTooltip(_en.savedRemove));
      await tester.pump();

      // Assert
      expect(find.text(_en.savedPlaceholderBody), findsOneWidget);
    });

    testWidgets('shows how long a fresh entry has left to live', (
      tester,
    ) async {
      // Arrange: fetched 19 hours ago, so 5 of the 24 remain.
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(
              _woltRef,
              DateTime.now().subtract(const Duration(hours: 19)),
              venueName: 'Vitrina',
            ),
          ),
        );
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.savedExpiresHours(5)), findsOneWidget);
    });

    testWidgets('an entry past its window reads as expired', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(
              _woltRef,
              DateTime.now().subtract(const Duration(days: 3)),
              venueName: 'Vitrina',
            ),
          ),
        );
      final controller = h.controller;

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.savedExpired), findsOneWidget);
    });

    testWidgets('the remove icon is red ink in both themes and the pin '
        'stays neutral (#254)', (tester) async {
      for (final (theme, verdicts) in [
        (AppTheme.light(), VerdictColors.light()),
        (AppTheme.dark(), VerdictColors.dark()),
      ]) {
        // Arrange
        final h = _Harness()
          ..open(
            CachedMenu(
              menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
            ),
          );
        final controller = h.controller;
        await _pump(tester, controller, theme: theme);
        await tester.pumpAndSettle();

        // Assert
        Icon iconIn(String tooltip) => tester.widget<Icon>(
          find.descendant(
            of: find.byTooltip(tooltip),
            matching: find.byType(Icon),
          ),
        );
        expect(iconIn(_en.savedRemove).color, verdicts.red.ink);
        expect(iconIn(_en.savedKeep).color, isNull);
      }
    });

    testWidgets('the pin toggle keeps an entry and replaces its countdown, '
        'and a second tap lets it expire again', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(
              _woltRef,
              DateTime.now().subtract(const Duration(hours: 19)),
              venueName: 'Vitrina',
            ),
          ),
        );
      final controller = h.controller;
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act: keep it.
      await tester.tap(find.byTooltip(_en.savedKeep));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.savedKept), findsOneWidget);
      expect(find.text(_en.savedExpiresHours(5)), findsNothing);
      expect(h.repository.pinCalls.single, (ref: _woltRef, pinned: true));

      // Act: stop keeping it.
      await tester.tap(find.byTooltip(_en.savedUnkeep));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.savedKept), findsNothing);
      expect(find.text(_en.savedExpiresHours(5)), findsOneWidget);
    });

    group('a row the cache no longer holds (issue #313)', () {
      testWidgets('reads not on this device, shows the snapshot counts, '
          'has no pin or engine chip, and still opens', (tester) async {
        // Arrange
        final h = _Harness()
          ..visit(
            _woltRef,
            name: 'Vitrina',
            city: 'Tel Aviv',
            dishCount: 12,
            score: 5,
            greenCount: 4,
            yellowCount: 2,
          );
        Object? forwardedArgs;
        String? navigated;
        await _pump(
          tester,
          h.controller,
          onNavigate: (name) => navigated = name,
          onNavigateArguments: (args) => forwardedArgs = args,
        );
        await tester.pumpAndSettle();

        // Assert: listed from the history alone.
        expect(find.text('Vitrina'), findsOneWidget);
        expect(find.text(_en.savedNotOnDevice), findsOneWidget);
        expect(find.text(_en.savedEntryDishCount(12)), findsOneWidget);
        expect(find.text('5.0'), findsOneWidget);
        expect(find.text(_en.venueCardGreenCount(4)), findsOneWidget);
        expect(find.text(_en.venueCardYellowCount(2)), findsOneWidget);
        expect(find.byType(EngineChip), findsNothing);
        expect(find.byTooltip(_en.savedKeep), findsNothing);
        expect(find.byTooltip(_en.savedRemove), findsOneWidget);

        // Act
        await tester.tap(find.text('Vitrina'));
        await tester.pumpAndSettle();

        // Assert: it opens online, with the name and city it was shown
        // under.
        expect(navigated, '/venue/wolt/${_woltRef.platformId}');
        expect(
          forwardedArgs,
          const VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv'),
        );
      });

      testWidgets('hides the counts row when neither side has a number', (
        tester,
      ) async {
        // Arrange
        final h = _Harness()..visit(_woltRef, name: 'Vitrina');

        // Act
        await _pump(tester, h.controller);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Vitrina'), findsOneWidget);
        expect(find.byType(Wrap), findsNothing);
        expect(find.byType(KetoScoreBadge), findsNothing);
      });

      testWidgets('a scan reads no longer on this device, is disabled with '
          'no pin, and can still be removed', (tester) async {
        // Arrange
        const scanRef = VenueRef(source: MenuSource.scan, platformId: 'beef');
        final h = _Harness()..visit(scanRef);
        String? navigated;
        await _pump(
          tester,
          h.controller,
          onNavigate: (name) => navigated = name,
        );
        await tester.pumpAndSettle();

        // Assert: listed, gone, disabled, unpinnable.
        expect(find.text(_en.savedScanGone), findsOneWidget);
        expect(find.text(_en.savedNotOnDevice), findsNothing);
        final tile = tester.widget<ListTile>(find.byType(ListTile));
        expect(tile.enabled, isFalse);
        expect(tile.onTap, isNull);
        expect(find.byTooltip(_en.savedKeep), findsNothing);
        expect(find.byTooltip(_en.savedUnkeep), findsNothing);

        // Act: a tap on the row goes nowhere.
        await tester.tap(find.text(_en.sourceScanned));
        await tester.pumpAndSettle();

        // Assert
        expect(navigated, isNull);

        // Act: remove it and let the undo window run out.
        await tester.tap(find.byTooltip(_en.savedRemove));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.savedScanGone), findsNothing);
        expect(h.history.removedRefs, [scanRef]);
        expect(h.repository.removedRefs, [scanRef]);
      });

      testWidgets('a gone scan can be swiped away', (tester) async {
        // Arrange
        const scanRef = VenueRef(source: MenuSource.scan, platformId: 'beef');
        final h = _Harness()..visit(scanRef);
        await _pump(tester, h.controller);
        await tester.pumpAndSettle();

        // Act
        await tester.drag(find.byType(ListTile), const Offset(-600, 0));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.savedScanGone), findsNothing);
        expect(
          find.text(_en.savedRemovedMessage(_en.sourceScanned)),
          findsOneWidget,
        );
      });
    });

    testWidgets('a kept cached menu reads kept, no expiry', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(
              _woltRef,
              DateTime.now().subtract(const Duration(days: 3)),
              venueName: 'Vitrina',
            ),
          ),
        );
      await h.repository.pin(_woltRef);

      // Act
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.savedKept), findsOneWidget);
      expect(find.text(_en.savedExpired), findsNothing);
      expect(find.byTooltip(_en.savedUnkeep), findsOneWidget);
    });

    testWidgets('the visit name wins over the cached menu name, which wins '
        'over the reference (issue #313)', (tester) async {
      // Arrange
      const otherRef = VenueRef(source: MenuSource.wolt, platformId: 'other');
      final now = DateTime.now();
      final h = _Harness()
        ..open(
          CachedMenu(menu: _menuWith(_woltRef, now, venueName: 'Cached Name')),
          name: 'Visit Name',
        )
        ..open(
          CachedMenu(menu: _menuWith(otherRef, now, venueName: 'Only Cached')),
        );

      // Act
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Visit Name'), findsOneWidget);
      expect(find.text('Cached Name'), findsNothing);
      expect(find.text('Only Cached'), findsOneWidget);
      expect(find.text('other'), findsNothing);
    });

    testWidgets('the source line names the city and when the menu was '
        'last opened (issue #313)', (tester) async {
      // Arrange: fetched a day ago, opened two hours ago.
      final now = DateTime.now();
      final h = _Harness()
        ..open(
          CachedMenu(
            menu: _menuWith(
              _woltRef,
              now.subtract(const Duration(days: 1)),
              venueName: 'Vitrina',
            ),
          ),
          openedAt: now.subtract(const Duration(hours: 2)),
          city: 'Tel Aviv',
        );

      // Act
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(
          _en.menuSourceLine(
            _en.sourceWithCity('Wolt', 'Tel Aviv'),
            _en.savedOpenedAgo(_en.ageHours(2)),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the source line leaves out an unknown city', (tester) async {
      // Arrange
      final now = DateTime.now();
      final h = _Harness()
        ..open(
          CachedMenu(menu: _menuWith(_woltRef, now, venueName: 'Vitrina')),
          openedAt: now.subtract(const Duration(hours: 2)),
        );

      // Act
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(
          _en.menuSourceLine('Wolt', _en.savedOpenedAgo(_en.ageHours(2))),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows how often a menu was opened, only once it was opened '
        'more than once', (tester) async {
      // Arrange
      const otherRef = VenueRef(source: MenuSource.wolt, platformId: 'other');
      final now = DateTime.now();
      final h = _Harness()
        ..open(
          CachedMenu(menu: _menuWith(_woltRef, now, venueName: 'Vitrina')),
          openCount: 3,
        )
        ..open(CachedMenu(menu: _menuWith(otherRef, now, venueName: 'Once')));

      // Act
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.savedOpenCount(3)), findsOneWidget);
      expect(find.text(_en.savedOpenCount(1)), findsNothing);
    });

    testWidgets('a cached menu with no visit is not listed', (tester) async {
      // Arrange
      final h = _Harness();
      h.repository.seedCache(
        CachedMenu(
          menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
        ),
      );

      // Act
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Vitrina'), findsNothing);
      expect(find.text(_en.savedPlaceholderBody), findsOneWidget);
    });
  });

  group('renaming a scanned row (issue #315)', () {
    const scanRef = VenueRef(source: MenuSource.scan, platformId: 'beef');

    /// Every custom action label on [root] and below, in tree order.
    List<String> customActionLabels(SemanticsNode root) {
      final labels = <String>[];
      void visit(SemanticsNode node) {
        for (final id
            in node.getSemanticsData().customSemanticsActionIds ??
                const <int>[]) {
          final action = CustomSemanticsAction.getAction(id);
          if (action != null) labels.add(action.label!);
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(root);
      return labels;
    }

    testWidgets('a long-press on a scan row opens the dialog, prefilled; '
        'saving renames the row and the store', (tester) async {
      // Arrange
      final h = _Harness()
        ..open(
          CachedMenu(menu: _menuWith(scanRef, DateTime.now().toUtc())),
          name: 'Old name',
          city: 'Lod',
        );
      await h.controller.load();
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Act
      await tester.longPress(find.text('Old name'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.menuRenameTitle), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('menuRenameName')))
            .controller!
            .text,
        'Old name',
      );

      // Act
      await tester.enterText(
        find.byKey(const ValueKey('menuRenameName')),
        'Café Noam',
      );
      await tester.enterText(
        find.byKey(const ValueKey('menuRenameCity')),
        'Haifa',
      );
      await tester.tap(find.byKey(const ValueKey('menuRenameSave')));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Café Noam'), findsOneWidget);
      expect(find.text('Old name'), findsNothing);
      expect(
        find.textContaining(_en.sourceWithCity(_en.sourceScanned, 'Haifa')),
        findsOneWidget,
      );
      final stored = await h.history.read(scanRef);
      expect(stored!.name, 'Café Noam');
      expect(stored.city, 'Haifa');
    });

    testWidgets('a long-press on a Wolt row opens nothing', (tester) async {
      // Arrange
      final h = _Harness()..visit(_woltRef, name: 'Vitrina');
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Act
      await tester.longPress(find.text('Vitrina'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a gone scan row can still be renamed', (tester) async {
      // Arrange
      final h = _Harness()..visit(scanRef);
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();
      expect(find.text(_en.savedScanGone), findsOneWidget);

      // Act
      await tester.longPress(find.text(_en.sourceScanned));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('menuRenameName')),
        'Café Noam',
      );
      await tester.tap(find.byKey(const ValueKey('menuRenameSave')));
      await tester.pumpAndSettle();

      // Assert: renamed, and still gone.
      expect(find.text('Café Noam'), findsOneWidget);
      expect(find.text(_en.savedScanGone), findsOneWidget);
      expect((await h.history.read(scanRef))!.name, 'Café Noam');
    });

    testWidgets('cancelling the dialog renames nothing', (tester) async {
      // Arrange
      final h = _Harness()..visit(scanRef, name: 'Old name');
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Act
      await tester.longPress(find.text('Old name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.actionCancel));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Old name'), findsOneWidget);
      expect(h.history.renameCalls, isEmpty);
    });

    testWidgets('a scan row offers a Rename screen-reader action named for '
        'it, and a Wolt row does not', (tester) async {
      // Arrange
      final semantics = tester.ensureSemantics();
      final h = _Harness()
        ..visit(scanRef, name: 'Old name')
        ..visit(_woltRef, name: 'Vitrina');
      await _pump(tester, h.controller);
      await tester.pumpAndSettle();

      // Assert
      Iterable<String> labelsOf(String title) => customActionLabels(
        tester.getSemantics(
          find.ancestor(
            of: find.text(title),
            matching: find.byType(Dismissible),
          ),
        ),
      );
      expect(labelsOf('Old name'), [_en.savedRenameSemanticLabel('Old name')]);
      expect(labelsOf('Vitrina'), isEmpty);
      semantics.dispose();
    });
  });

  group('cacheExpiryLabel', () {
    final now = DateTime.utc(2026, 6, 1, 12);

    String label(Duration remaining, {Duration ttl = const Duration(days: 3)}) {
      // fetchedAt is chosen so that exactly [remaining] is left of [ttl].
      return cacheExpiryLabel(
        now.add(remaining).subtract(ttl),
        now,
        _en,
        ttl: ttl,
      );
    }

    test('reads minutes under an hour, rounding a partial minute up', () {
      expect(label(const Duration(minutes: 40)), _en.savedExpiresMinutes(40));
      expect(
        label(const Duration(minutes: 39, seconds: 1)),
        _en.savedExpiresMinutes(40),
      );
      expect(label(const Duration(seconds: 10)), _en.savedExpiresMinutes(1));
    });

    test('reads hours from an hour up to a day', () {
      expect(label(const Duration(hours: 1)), _en.savedExpiresHours(1));
      expect(label(const Duration(hours: 5)), _en.savedExpiresHours(5));
      expect(
        label(const Duration(hours: 23, minutes: 30)),
        _en.savedExpiresHours(23),
      );
    });

    test('reads days from a day up', () {
      expect(label(const Duration(days: 1)), _en.savedExpiresDays(1));
      expect(label(const Duration(days: 2)), _en.savedExpiresDays(2));
    });

    test('defaults to the 24-hour cache window', () {
      expect(
        cacheExpiryLabel(now.subtract(const Duration(hours: 19)), now, _en),
        _en.savedExpiresHours(5),
      );
    });

    test('reads expired at and past the end of the window', () {
      expect(label(Duration.zero), _en.savedExpired);
      expect(label(const Duration(minutes: -5)), _en.savedExpired);
    });

    test('reads in Hebrew too', () {
      final he = AppLocalizationsHe();
      expect(
        cacheExpiryLabel(now.subtract(const Duration(hours: 19)), now, he),
        he.savedExpiresHours(5),
      );
    });
  });
}
