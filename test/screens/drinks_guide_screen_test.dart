// Tests for the offline bilingual drinks guide screen (issue #216, Part B).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/screens/drinks_guide_screen.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// English strings for the tests.
final AppLocalizations _en = AppLocalizationsEn();

/// Hebrew strings for the RTL test.
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps [DrinksGuideScreen] inside a localised [MaterialApp] under
/// [locale].  The screen has no controller dependency, so no fakes needed.
Future<void> _pump(WidgetTester tester, {Locale locale = const Locale('en')}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DrinksGuideScreen(),
    ),
  );
}

void main() {
  group('DrinksGuideScreen', () {
    // -------------------------------------------------------------------------
    // Three sections are present
    // -------------------------------------------------------------------------

    testWidgets('all three section headers are visible in English', (
      tester,
    ) async {
      // Arrange + Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.drinksGuideSectionOrderAsIs), findsOneWidget);
      expect(find.text(_en.drinksGuideSectionSwap), findsOneWidget);
      expect(find.text(_en.drinksGuideSectionSkip), findsOneWidget);
    });

    testWidgets('app bar shows the drinks guide title', (tester) async {
      // Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.drinksGuideTitle), findsOneWidget);
    });

    testWidgets('the disclaimer is shown', (tester) async {
      // Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.drinksGuideDisclaimer), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Swap section has WaiterScriptWidget (copy affordance)
    // -------------------------------------------------------------------------

    testWidgets(
      'the "ask for a swap" section renders at least one WaiterScriptWidget',
      (tester) async {
        // Act
        await _pump(tester);
        await tester.pumpAndSettle();

        // Assert — at least one swap-script widget in the tree
        expect(find.byType(WaiterScriptWidget), findsWidgets);
      },
    );

    testWidgets('at 1440px the guide reads in a centred column no wider '
        'than the cap (issue #221)', (tester) async {
      // Arrange
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      final column = tester.getRect(
        find
            .descendant(
              of: find.byType(ContentWidth),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(column.width, contentMaxWidth);
      expect(column.center.dx, 720);
    });

    // -------------------------------------------------------------------------
    // Hebrew / RTL
    // -------------------------------------------------------------------------

    testWidgets('under Locale(he) section headers are Hebrew', (tester) async {
      // Act
      await _pump(tester, locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.drinksGuideSectionOrderAsIs), findsOneWidget);
      expect(find.text(_he.drinksGuideSectionSwap), findsOneWidget);
      expect(find.text(_he.drinksGuideSectionSkip), findsOneWidget);
    });

    testWidgets(
      'under Locale(he) the screen renders under RTL directionality',
      (tester) async {
        // Act
        await _pump(tester, locale: const Locale('he'));
        await tester.pumpAndSettle();

        // Assert — directionality is RTL for the whole screen
        final context = tester.element(find.byType(DrinksGuideScreen));
        expect(Directionality.of(context), TextDirection.rtl);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
