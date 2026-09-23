import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

/// Pumps the real [VenueSearchScreen] over a real
/// [VenueSearchController], recording every route name pushed via
/// [Navigator.pushNamed] into [pushedNames].
Future<void> _pump(
  WidgetTester tester, {
  required VenueSearchController controller,
  required List<String> pushedNames,
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    ChangeNotifierProvider<VenueSearchController>.value(
      value: controller,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const VenueSearchScreen(),
        onGenerateRoute: (settings) {
          pushedNames.add(settings.name ?? '');
          return MaterialPageRoute<void>(
            builder: (_) => const SizedBox.shrink(),
            settings: settings,
          );
        },
      ),
    ),
  );
}

void main() {
  group('VenueSearchScreen', () {
    late FakeSettingsStore settingsStore;
    late FakeMenuRepository repository;
    late VenueSearchController controller;
    late List<String> pushedNames;

    setUp(() {
      settingsStore = FakeSettingsStore();
      repository = FakeMenuRepository();
      controller = VenueSearchController(settingsStore, repository);
      pushedNames = <String>[];
    });

    testWidgets('build renders the brand, the title and the search field', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final context = tester.element(find.byType(VenueSearchScreen));
      final l10n = AppLocalizations.of(context)!;

      // Assert
      expect(find.text(appName), findsOneWidget);
      expect(find.text(l10n.discoveryTitle), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('build has no app bar: Settings is reached from the bottom nav '
        'shell, not a duplicate icon here', (tester) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Assert
      expect(find.byType(AppBar), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets(
      'the empty state explains that only a link works today, standing '
      "in for the artboard's search results and filter chips",
      (tester) async {
        // Act
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        final context = tester.element(find.byType(VenueSearchScreen));
        final l10n = AppLocalizations.of(context)!;

        // Assert
        expect(find.text(l10n.discoveryEmptyTitle), findsOneWidget);
        expect(find.text(l10n.discoveryEmptyBody), findsOneWidget);
      },
    );

    testWidgets('typing nonsense shows the venueSearchInvalid message', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final context = tester.element(find.byType(VenueSearchScreen));
      final l10n = AppLocalizations.of(context)!;

      // Act
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/nope',
      );
      await tester.pump();

      // Assert
      expect(find.text(l10n.venueSearchInvalid), findsOneWidget);
    });

    testWidgets('an empty field shows no invalid message', (tester) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      final context = tester.element(find.byType(VenueSearchScreen));
      final l10n = AppLocalizations.of(context)!;

      // Assert: nothing typed yet.
      expect(find.text(l10n.venueSearchInvalid), findsNothing);
    });

    testWidgets('typing a valid slug enables the submit affordance', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller: controller, pushedNames: pushedNames);

      // Assert: disabled before anything resolves.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      // Act
      await tester.enterText(find.byType(TextField), 'vitrina-lilinblum');
      await tester.pump();

      // Assert
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'tapping the submit affordance pushes the venue route path for a '
      'Wolt slug',
      (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.enterText(find.byType(TextField), 'vitrina-lilinblum');
        await tester.pump();

        // Act
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/venue/wolt/vitrina-lilinblum'));
      },
    );

    testWidgets(
      'a pasted 10bis id resolves and pushes a tenbis venue route — the '
      "unsupportedSource message it hits from there is MenuScreen's job, "
      'not this one',
      (tester) async {
        // Arrange
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();

        // Act
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/venue/tenbis/123456'));
      },
    );

    testWidgets('build under Locale(he) renders the Hebrew title', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        controller: controller,
        pushedNames: pushedNames,
        locale: const Locale('he'),
      );
      final context = tester.element(find.byType(VenueSearchScreen));
      final l10n = AppLocalizations.of(context)!;

      // Assert
      expect(find.text(l10n.venueSearchLabel), findsOneWidget);
      expect(find.text(l10n.discoveryTitle), findsOneWidget);
      expect(find.text(l10n.discoveryEmptyBody), findsOneWidget);
    });

    testWidgets('no lastVenue stored shows no Continue row (issue #55)', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller: controller, pushedNames: pushedNames);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byIcon(Icons.history), findsNothing);
    });

    testWidgets(
      'launch with a stored lastVenue shows the Continue row and tapping '
      'it navigates to the venue route (issue #55)',
      (tester) async {
        // Arrange
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
        await settingsStore.write(const AppSettings(lastVenue: ref));
        repository.seedCache(
          CachedMenu(
            menu: Menu(
              venueRef: ref,
              venueName: 'Vitrina',
              currency: 'ILS',
              fetchedAt: DateTime.utc(2026),
              categories: const <MenuCategory>[],
            ),
          ),
        );

        // Act
        await _pump(tester, controller: controller, pushedNames: pushedNames);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(VenueSearchScreen));
        final l10n = AppLocalizations.of(context)!;

        // Assert: the row shows the cached venue name.
        expect(
          find.text(l10n.venueSearchContinueWith('Vitrina')),
          findsOneWidget,
        );

        // Act: tap it.
        await tester.tap(find.text(l10n.venueSearchContinueWith('Vitrina')));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/venue/wolt/vitrina'));
      },
    );
  });
}
