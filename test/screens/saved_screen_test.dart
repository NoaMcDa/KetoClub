import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/saved_screen.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/state/saved_controller.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_menu_repository.dart';

/// The English strings a test can read expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the RTL test.
final AppLocalizations _he = AppLocalizationsHe();

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

Future<void> _pump(
  WidgetTester tester,
  SavedController controller, {
  Locale locale = const Locale('en'),
  ValueChanged<String>? onNavigate,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) {
          if (settings.name != '/') onNavigate?.call(settings.name!);
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

void main() {
  group('SavedScreen', () {
    testWidgets('shows the reworked empty state when nothing is cached', (
      tester,
    ) async {
      // Arrange
      final controller = SavedController(FakeMenuRepository());

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.savedPlaceholderTitle), findsOneWidget);
      expect(find.text(_en.savedPlaceholderBody), findsOneWidget);
    });

    testWidgets('lists a cached menu with its venue name, source line and '
        'dish count', (tester) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..seedCache(
          CachedMenu(
            menu: _menuWith(
              _woltRef,
              DateTime.now(),
              dishes: 3,
              venueName: 'Vitrina',
            ),
          ),
        );
      final controller = SavedController(repository);

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
      final repository = FakeMenuRepository()
        ..seedCache(CachedMenu(menu: _menuWith(_woltRef, DateTime.now())));
      final controller = SavedController(repository);

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_woltRef.platformId), findsOneWidget);
    });

    testWidgets('shows an EngineChip for an analysed entry', (tester) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..seedCache(
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
      final controller = SavedController(repository);

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(EngineChip), findsOneWidget);
    });

    testWidgets('lists the newest-fetched menu first', (tester) async {
      // Arrange
      const olderRef = VenueRef(source: MenuSource.wolt, platformId: 'older');
      const newerRef = VenueRef(source: MenuSource.wolt, platformId: 'newer');
      final repository = FakeMenuRepository()
        ..seedCache(
          CachedMenu(
            menu: _menuWith(
              olderRef,
              DateTime.utc(2026),
              venueName: 'Older Place',
            ),
          ),
        )
        ..seedCache(
          CachedMenu(
            menu: _menuWith(
              newerRef,
              DateTime.utc(2026, 1, 2),
              venueName: 'Newer Place',
            ),
          ),
        );
      final controller = SavedController(repository);

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final newerTop = tester.getTopLeft(find.text('Newer Place'));
      final olderTop = tester.getTopLeft(find.text('Older Place'));
      expect(newerTop.dy, lessThan(olderTop.dy));
    });

    testWidgets('tapping an entry navigates to its venue route', (
      tester,
    ) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..seedCache(
          CachedMenu(
            menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
          ),
        );
      final controller = SavedController(repository);
      String? navigated;

      // Act
      await _pump(tester, controller, onNavigate: (name) => navigated = name);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vitrina'));
      await tester.pumpAndSettle();

      // Assert
      expect(
        navigated,
        '/venue/${_woltRef.source.name}/${_woltRef.platformId}',
      );
      expect(find.text('pushed:$navigated'), findsOneWidget);
    });

    testWidgets('removing via the trailing action hides the row, shows an '
        'undo SnackBar, and undo restores it without touching the '
        'repository', (tester) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..seedCache(
          CachedMenu(
            menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
          ),
        );
      final controller = SavedController(repository);
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

      // Assert: restored, and the repository was never asked to delete.
      expect(find.text('Vitrina'), findsOneWidget);
      expect(repository.removedRefs, isEmpty);
    });

    testWidgets(
      'letting the undo SnackBar close without tapping undo deletes from '
      'the repository',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..seedCache(
            CachedMenu(
              menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
            ),
          );
        final controller = SavedController(repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.byTooltip(_en.savedRemove));
        // pumpAndSettle's argument is the frame step, not elapsed time, so
        // it returns once the SnackBar's entrance animation ends, before
        // its auto-dismiss timer fires. Advance the clock past that timer,
        // then settle the exit animation so `closed` completes.
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Assert
        expect(repository.removedRefs, [_woltRef]);
      },
    );

    testWidgets('an empty list shown after removing the only entry reads '
        'as the empty state', (tester) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..seedCache(
          CachedMenu(
            menu: _menuWith(_woltRef, DateTime.now(), venueName: 'Vitrina'),
          ),
        );
      final controller = SavedController(repository);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.byTooltip(_en.savedRemove));
      await tester.pump();

      // Assert
      expect(find.text(_en.savedPlaceholderBody), findsOneWidget);
    });

    testWidgets('build under Locale(he) renders the Hebrew empty copy', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        SavedController(FakeMenuRepository()),
        locale: const Locale('he'),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.savedPlaceholderTitle), findsOneWidget);
      expect(find.text(_he.savedPlaceholderBody), findsOneWidget);
    });
  });
}
