import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/utils/known_places.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/location_picker_sheet.dart';

/// Pumps a page with one button that opens the picker with [selected]
/// marked, and records what each opening completes with in [picks].
Future<void> _pump(
  WidgetTester tester, {
  required List<LocationPick?> picks,
  KnownPlace? selected,
  Locale locale = const Locale('en'),
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
              await showLocationPickerSheet(context, selected: selected),
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
}
