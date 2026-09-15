import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/screens/saved_screen.dart';

/// The English strings a test can read expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the RTL test.
final AppLocalizations _he = AppLocalizationsHe();

Future<void> _pump(WidgetTester tester, {Locale locale = const Locale('en')}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: const SavedScreen(),
    ),
  );
}

void main() {
  group('SavedScreen', () {
    testWidgets('shows the localized placeholder title and body', (
      tester,
    ) async {
      // Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.savedPlaceholderTitle), findsOneWidget);
      expect(find.text(_en.savedPlaceholderBody), findsOneWidget);
    });

    testWidgets('build under Locale(he) renders the Hebrew copy', (
      tester,
    ) async {
      // Act
      await _pump(tester, locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.savedPlaceholderTitle), findsOneWidget);
      expect(find.text(_he.savedPlaceholderBody), findsOneWidget);
    });
  });
}
