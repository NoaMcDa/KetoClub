import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/place/place_search_service.dart';
import 'package:ketoclub/utils/known_places.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/location_picker_sheet.dart';

/// Pumps a page with one button that opens the picker with [selected]
/// marked, and records what each opening completes with in [picks].
Future<void> _pump(
  WidgetTester tester, {
  required List<LocationPick?> picks,
  KnownPlace? selected,
  Locale locale = const Locale('en'),
  StreetSearch? searchStreets,
  bool throughBackend = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picks.add(
              await showLocationPickerSheet(
                context,
                selected: selected,
                searchStreets: searchStreets,
                streetSearchThroughBackend: throughBackend,
              ),
            ),
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    ),
  );
}

/// Opens the sheet by tapping the page's one button.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(TextButton));
  await tester.pumpAndSettle();
}

/// The localised strings of the open sheet.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(LocationPickerSheet)))!;

/// The row of the list naming [name].
Finder _row(String name) => find.widgetWithText(ListTile, name);

void main() {
  group('LocationPickerSheet (issue #443)', () {
    testWidgets('shows its title, the device row, the search field and the '
        'places in English', (tester) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);

      // Act
      await _open(tester);
      final l10n = _l10n(tester);

      // Assert
      expect(find.text(l10n.locationPickerTitle), findsOneWidget);
      expect(find.text(l10n.locationPickerUseDevice), findsOneWidget);
      expect(find.text(l10n.locationPickerSearchLabel), findsOneWidget);
      expect(_row('Tel Aviv-Yafo'), findsOneWidget);
      expect(_row('Jerusalem'), findsOneWidget);
      expect(_row('Haifa'), findsOneWidget);
      expect(find.text('חיפה'), findsNothing);
      expect(picks, isEmpty);
    });

    testWidgets('names the places in Hebrew under Hebrew', (tester) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks, locale: const Locale('he'));

      // Act
      await _open(tester);
      final l10n = _l10n(tester);

      // Assert
      expect(l10n.localeName, 'he');
      expect(find.text(l10n.locationPickerTitle), findsOneWidget);
      expect(_row('חיפה'), findsOneWidget);
      expect(find.text('Haifa'), findsNothing);
    });

    testWidgets('tapping a place closes the sheet with that place', (
      tester,
    ) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);
      await _open(tester);

      // Act
      await tester.tap(_row('Haifa'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(LocationPickerSheet), findsNothing);
      final pick = picks.single;
      expect(pick, isA<LocationPickPlace>());
      expect((pick! as LocationPickPlace).place, knownPlaceById('haifa'));
    });

    testWidgets('tapping "Use my current location" closes the sheet with '
        'the device answer', (tester) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);
      await _open(tester);

      // Act
      await tester.tap(find.text(_l10n(tester).locationPickerUseDevice));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(LocationPickerSheet), findsNothing);
      expect(picks.single, isA<LocationPickDevice>());
    });

    testWidgets('dismissing the sheet completes with null', (tester) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);
      await _open(tester);

      // Act: a tap on the scrim above the sheet.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(LocationPickerSheet), findsNothing);
      expect(picks, <LocationPick?>[null]);
    });

    testWidgets('typing narrows the list, and a place found that way can '
        'be picked', (tester) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);
      await _open(tester);

      // Act
      await tester.enterText(find.byType(TextField), 'eil');
      await tester.pump();

      // Assert
      expect(_row('Eilat'), findsOneWidget);
      expect(_row('Haifa'), findsNothing);

      // Act
      await tester.tap(_row('Eilat'));
      await tester.pumpAndSettle();

      // Assert
      expect(
        (picks.single! as LocationPickPlace).place,
        knownPlaceById('eilat'),
      );
    });

    testWidgets('a Hebrew name finds its place under an English UI', (
      tester,
    ) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);
      await _open(tester);

      // Act
      await tester.enterText(find.byType(TextField), 'חיפה');
      await tester.pump();

      // Assert: found by its Hebrew name, shown by its English one.
      expect(_row('Haifa'), findsOneWidget);
      expect(_row('Jerusalem'), findsNothing);
    });

    testWidgets('says so when nothing matches, and keeps the device row', (
      tester,
    ) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);
      await _open(tester);
      final l10n = _l10n(tester);

      // Act
      await tester.enterText(find.byType(TextField), 'atlantis');
      await tester.pump();

      // Assert
      expect(find.text(l10n.locationPickerNoMatch), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
      expect(find.text(l10n.locationPickerUseDevice), findsOneWidget);
    });

    testWidgets('marks the place being looked around, and only that one', (
      tester,
    ) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks, selected: knownPlaceById('haifa'));

      // Act
      await _open(tester);

      // Assert
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(tester.widget<ListTile>(_row('Haifa')).selected, isTrue);
      expect(tester.widget<ListTile>(_row('Jerusalem')).selected, isFalse);
    });

    testWidgets('marks nothing when no place is chosen', (tester) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);

      // Act
      await _open(tester);

      // Assert
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('is no wider than the shared sheet cap on a wide window, and '
        'no taller than four fifths of it', (tester) async {
      // Arrange
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks);

      // Act
      await _open(tester);

      // Assert
      final size = tester.getSize(find.byType(LocationPickerSheet));
      expect(size.width, lessThanOrEqualTo(kSheetMaxWidth));
      expect(size.height, lessThanOrEqualTo(900 * 0.8));
    });
  });

  group('LocationPickerSheet street search (issue #449)', () {
    const herzl = StreetPlace(
      label: 'הרצל 10, תל אביב',
      city: 'תל אביב',
      latitude: 32.0625697,
      longitude: 34.7698648,
    );
    const dizengoff = StreetPlace(
      label: 'Dizengoff, Tel Aviv',
      latitude: 32.0765505,
      longitude: 34.7746435,
    );

    /// A street search that records each query and answers [answer].
    StreetSearch recording(
      List<String> queries, [
      PlaceSearchResult answer = const PlacesFound(<StreetPlace>[herzl]),
    ]) => (query) async {
      queries.add(query);
      return answer;
    };

    /// The street action's row for [text].
    Finder action(AppLocalizations l10n, String text) =>
        find.widgetWithText(ListTile, l10n.locationPickerStreetSearch(text));

    testWidgets('with the street action offered, points at it rather than '
        'at the spelling (issue #489)', (tester) async {
      // Arrange
      await _pump(tester, picks: [], searchStreets: recording([]));
      await _open(tester);
      final l10n = _l10n(tester);

      // Act
      await tester.enterText(find.byType(TextField), 'Dizengoff');
      await tester.pump();

      // Assert
      expect(find.text(l10n.locationPickerNoCityTryStreets), findsOneWidget);
      expect(find.text(l10n.locationPickerNoMatch), findsNothing);
      expect(
        find.text(l10n.locationPickerStreetSearch('Dizengoff')),
        findsOneWidget,
      );
    });

    testWidgets('offers the action only from three characters, and typing '
        'sends nothing', (tester) async {
      // Arrange
      final queries = <String>[];
      await _pump(tester, picks: [], searchStreets: recording(queries));
      await _open(tester);
      final l10n = _l10n(tester);

      // Act & Assert
      await tester.enterText(find.byType(TextField), 'he');
      await tester.pump();
      expect(action(l10n, 'he'), findsNothing);

      await tester.enterText(find.byType(TextField), ' her ');
      await tester.pump();
      expect(action(l10n, 'her'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'herzl 10');
      await tester.pump();
      expect(action(l10n, 'herzl 10'), findsOneWidget);
      expect(queries, isEmpty);
    });

    testWidgets('offers no street action without a street search', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, picks: []);
      await _open(tester);
      final l10n = _l10n(tester);

      // Act
      await tester.enterText(find.byType(TextField), 'herzl');
      await tester.pump();

      // Assert
      expect(action(l10n, 'herzl'), findsNothing);
      expect(find.text(l10n.locationPickerStreetCaptionDirect), findsNothing);
    });

    testWidgets('names Photon alone as where the text goes in a build with '
        'no backend (the Hebrew test covers the backend caption)', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, picks: [], searchStreets: recording([]));
      await _open(tester);
      final l10n = _l10n(tester);

      // Act
      await tester.enterText(find.byType(TextField), 'herzl');
      await tester.pump();

      // Assert
      expect(find.text(l10n.locationPickerStreetCaptionDirect), findsOneWidget);
      expect(find.text(l10n.locationPickerStreetCaptionBackend), findsNothing);
    });

    testWidgets('a tap runs one search for the trimmed text, shows progress, '
        'then the matches', (tester) async {
      // Arrange
      final queries = <String>[];
      final answer = Completer<PlaceSearchResult>();
      await _pump(
        tester,
        picks: [],
        searchStreets: (query) {
          queries.add(query);
          return answer.future;
        },
      );
      await _open(tester);
      final l10n = _l10n(tester);
      await tester.enterText(find.byType(TextField), ' dizengoff ');
      await tester.pump();

      // Act
      await tester.tap(action(l10n, 'dizengoff'));
      await tester.pump();

      // Assert: in flight.
      expect(queries, <String>['dizengoff']);
      expect(find.text(l10n.locationPickerStreetSearching), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Act
      answer.complete(const PlacesFound(<StreetPlace>[dizengoff, herzl]));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.locationPickerStreetSearching), findsNothing);
      expect(find.text(l10n.locationPickerStreetsHeading), findsOneWidget);
      expect(_row('Dizengoff, Tel Aviv'), findsOneWidget);
      expect(_row('הרצל 10, תל אביב'), findsOneWidget);
      expect(queries, hasLength(1));
    });

    testWidgets('picking a match closes the sheet with that street', (
      tester,
    ) async {
      // Arrange
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks, searchStreets: recording([]));
      await _open(tester);
      final l10n = _l10n(tester);
      await tester.enterText(find.byType(TextField), 'הרצל 10');
      await tester.pump();
      await tester.tap(action(l10n, 'הרצל 10'));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(_row('הרצל 10, תל אביב'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(LocationPickerSheet), findsNothing);
      expect(picks, hasLength(1));
      expect((picks.single! as LocationPickStreet).street, herzl);
    });

    testWidgets('says so when no street matches', (tester) async {
      // Arrange
      await _pump(
        tester,
        picks: [],
        searchStreets: recording([], const PlacesFound(<StreetPlace>[])),
      );
      await _open(tester);
      final l10n = _l10n(tester);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump();

      // Act
      await tester.tap(action(l10n, 'zzzz'));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(l10n.locationPickerStreetNoMatch('zzzz')),
        findsOneWidget,
      );
      expect(find.text(l10n.locationPickerStreetsHeading), findsNothing);
    });

    for (final reason in PlaceSearchFailureReason.values) {
      testWidgets('shows the ${reason.name} failure with a retry that '
          'searches again', (tester) async {
        // Arrange
        final queries = <String>[];
        final answers = <PlaceSearchResult>[
          PlaceSearchFailed(reason),
          const PlacesFound(<StreetPlace>[dizengoff]),
        ];
        await _pump(
          tester,
          picks: [],
          searchStreets: (query) async {
            queries.add(query);
            return answers.removeAt(0);
          },
        );
        await _open(tester);
        final l10n = _l10n(tester);
        await tester.enterText(find.byType(TextField), 'dizengoff');
        await tester.pump();
        await tester.tap(action(l10n, 'dizengoff'));
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.text(placeSearchFailureMessage(reason, l10n)),
          findsOneWidget,
        );

        // Act
        await tester.tap(find.text(l10n.actionRetry));
        await tester.pumpAndSettle();

        // Assert
        expect(queries, <String>['dizengoff', 'dizengoff']);
        expect(_row('Dizengoff, Tel Aviv'), findsOneWidget);
        expect(
          find.text(placeSearchFailureMessage(reason, l10n)),
          findsNothing,
        );
      });
    }

    testWidgets('editing the text drops the answer and offers the action '
        'again, and a late answer to older text is ignored', (tester) async {
      // Arrange
      final answer = Completer<PlaceSearchResult>();
      await _pump(tester, picks: [], searchStreets: (_) => answer.future);
      await _open(tester);
      final l10n = _l10n(tester);
      await tester.enterText(find.byType(TextField), 'herzl');
      await tester.pump();
      await tester.tap(action(l10n, 'herzl'));
      await tester.pump();

      // Act
      await tester.enterText(find.byType(TextField), 'herzl 1');
      await tester.pump();
      answer.complete(const PlacesFound(<StreetPlace>[herzl]));
      await tester.pumpAndSettle();

      // Assert
      expect(action(l10n, 'herzl 1'), findsOneWidget);
      expect(_row('הרצל 10, תל אביב'), findsNothing);
      expect(find.text(l10n.locationPickerStreetSearching), findsNothing);
    });

    testWidgets('a city still closes the sheet with no street search', (
      tester,
    ) async {
      // Arrange
      final queries = <String>[];
      final picks = <LocationPick?>[];
      await _pump(tester, picks: picks, searchStreets: recording(queries));
      await _open(tester);
      await tester.enterText(find.byType(TextField), 'haifa');
      await tester.pump();

      // Act
      await tester.tap(_row('Haifa'));
      await tester.pumpAndSettle();

      // Assert
      expect((picks.single! as LocationPickPlace).place.id, 'haifa');
      expect(queries, isEmpty);
    });

    testWidgets('reads in Hebrew under Hebrew, with the matches as the '
        'search wrote them', (tester) async {
      // Arrange
      await _pump(
        tester,
        picks: [],
        locale: const Locale('he'),
        searchStreets: recording([]),
        throughBackend: true,
      );
      await _open(tester);
      final l10n = _l10n(tester);
      await tester.enterText(find.byType(TextField), 'הרצל');
      await tester.pump();

      // Assert
      expect(find.text(l10n.locationPickerSearchLabel), findsOneWidget);
      expect(l10n.locationPickerSearchLabel, 'חיפוש עיר או רחוב');
      expect(action(l10n, 'הרצל'), findsOneWidget);
      expect(
        find.text(l10n.locationPickerStreetCaptionBackend),
        findsOneWidget,
      );

      // Act
      await tester.tap(action(l10n, 'הרצל'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('רחובות'), findsOneWidget);
      expect(_row('הרצל 10, תל אביב'), findsOneWidget);
    });
  });
}
