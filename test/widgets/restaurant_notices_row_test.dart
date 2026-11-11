import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/widgets/restaurant_notices_row.dart';

/// The English strings, read directly rather than through a widget tree.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings, read directly rather than through a widget tree.
final AppLocalizations _he = AppLocalizationsHe();

/// A zero-priced notice line named [name].
Dish _notice(String name, {String description = '', String id = 'n1'}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 0,
  options: const <DishOption>[],
);

/// Pumps a [RestaurantNoticesRow] over [notices] in a localised app.
Future<void> _pump(
  WidgetTester tester, {
  required List<Dish> notices,
  required bool expanded,
  VoidCallback? onToggle,
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: RestaurantNoticesRow(
          notices: notices,
          expanded: expanded,
          onToggle: onToggle ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('RestaurantNoticesRow (issue #445)', () {
    final allergens = _notice(
      'Allergen information',
      description: 'Ask the restaurant about allergens.',
    );
    final closing = _notice('Closed on Sunday', id: 'n2');

    testWidgets('collapsed, it shows how many notices there are and none of '
        'their text', (tester) async {
      // Act
      await _pump(tester, notices: [allergens, closing], expanded: false);

      // Assert
      expect(find.text(_en.menuRestaurantNotices(2)), findsOneWidget);
      expect(find.text('Allergen information'), findsNothing);
      expect(find.text('Closed on Sunday'), findsNothing);
    });

    testWidgets('the label is singular for one notice', (tester) async {
      // Act
      await _pump(tester, notices: [allergens], expanded: false);

      // Assert
      expect(find.text('1 note from the restaurant'), findsOneWidget);
    });

    testWidgets('expanded, it shows each notice as the restaurant wrote '
        'it', (tester) async {
      // Act
      await _pump(tester, notices: [allergens, closing], expanded: true);

      // Assert
      expect(find.text('Allergen information'), findsOneWidget);
      expect(find.text('Ask the restaurant about allergens.'), findsOneWidget);
      expect(find.text('Closed on Sunday'), findsOneWidget);
    });

    testWidgets('a notice with no description shows its name alone', (
      tester,
    ) async {
      // Act
      await _pump(tester, notices: [closing], expanded: true);

      // Assert: one Text for the label, one for the name.
      expect(find.byType(Text), findsNWidgets(2));
    });

    testWidgets('tapping the row calls onToggle', (tester) async {
      // Arrange
      var toggles = 0;
      await _pump(
        tester,
        notices: [allergens],
        expanded: false,
        onToggle: () => toggles++,
      );

      // Act
      await tester.tap(find.text(_en.menuRestaurantNotices(1)));

      // Assert
      expect(toggles, 1);
    });

    for (final expanded in [false, true]) {
      testWidgets('it is announced as a button whose expanded flag is '
          '$expanded', (tester) async {
        // Arrange
        final handle = tester.ensureSemantics();

        // Act
        await _pump(tester, notices: [allergens], expanded: expanded);

        // Assert
        final node = tester.getSemantics(
          find.bySemanticsLabel(_en.menuRestaurantNotices(1)),
        );
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isExpanded.toBoolOrNull(), expanded);
        handle.dispose();
      });
    }

    testWidgets('the label is Hebrew in the he locale', (tester) async {
      // Act
      await _pump(
        tester,
        notices: [allergens, closing],
        expanded: false,
        locale: const Locale('he'),
      );

      // Assert
      expect(find.text(_he.menuRestaurantNotices(2)), findsOneWidget);
      expect(_he.menuRestaurantNotices(2), contains('הודעות'));
    });
  });
}
