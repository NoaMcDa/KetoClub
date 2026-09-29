import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/screens/scan_screen.dart';
import 'package:ketoclub/state/scan_controller.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';

/// The English strings a test can read expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the RTL test.
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps the screen over [controller]. Every route other than `/` is
/// recorded into [pushed] and answered with a marker widget.
Future<void> _pump(
  WidgetTester tester,
  ScanController controller, {
  Locale locale = const Locale('en'),
  List<String>? pushed,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) {
          if (settings.name == '/') {
            return ChangeNotifierProvider<ScanController>.value(
              value: controller,
              child: const ScanScreen(),
            );
          }
          pushed?.add(settings.name!);
          return Text('pushed:${settings.name}');
        },
      ),
    ),
  );
}

ScanController _controller(FakeMenuRepository repository) => ScanController(
  repository: repository,
  clock: FakeClock(DateTime.utc(2026, 9, 29)),
);

/// The Analyse button, found by its label.
Finder _analyse(AppLocalizations l10n) =>
    find.widgetWithText(ElevatedButton, l10n.scanAnalyse);

void main() {
  group('ScanScreen', () {
    late FakeMenuRepository repository;
    late ScanController controller;

    setUp(() {
      repository = FakeMenuRepository();
      controller = _controller(repository);
    });

    tearDown(() => controller.dispose());

    testWidgets('shows the localized title, intro and paste field', (
      tester,
    ) async {
      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanTitle), findsOneWidget);
      expect(find.text(_en.scanPasteIntro), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(_analyse(_en), findsOneWidget);
    });

    testWidgets(
      'build under Locale(he) renders the Hebrew copy, right to left',
      (tester) async {
        // Act
        await _pump(tester, controller, locale: const Locale('he'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_he.scanTitle), findsOneWidget);
        expect(find.text(_he.scanPasteIntro), findsOneWidget);
        expect(_analyse(_he), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.byType(TextField))),
          TextDirection.rtl,
        );
      },
    );

    testWidgets('Analyse is disabled while the field is empty', (tester) async {
      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(tester.widget<ElevatedButton>(_analyse(_en)).onPressed, isNull);
    });

    testWidgets('Analyse stays disabled for whitespace only', (tester) async {
      // Arrange
      await _pump(tester, controller);

      // Act
      await tester.enterText(find.byType(TextField), '   \n ');
      await tester.pump();

      // Assert
      expect(tester.widget<ElevatedButton>(_analyse(_en)).onPressed, isNull);
    });

    testWidgets('typing enables Analyse', (tester) async {
      // Arrange
      await _pump(tester, controller);

      // Act
      await tester.enterText(find.byType(TextField), 'Grilled salmon');
      await tester.pump();

      // Assert
      expect(tester.widget<ElevatedButton>(_analyse(_en)).onPressed, isNotNull);
    });

    testWidgets('Analyse stores the menu and opens /venue/scan/{id}', (
      tester,
    ) async {
      // Arrange
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);
      await tester.enterText(
        find.byType(TextField),
        'Grilled salmon 68 ₪\nCaesar salad',
      );
      await tester.pump();

      // Act
      await tester.tap(_analyse(_en));
      await tester.pumpAndSettle();

      // Assert
      final stored = repository.storedMenus.single;
      expect(pushed, ['/venue/scan/${stored.venueRef.platformId}']);
      expect(stored.allDishes.map((d) => d.name), [
        'Grilled salmon',
        'Caesar salad',
      ]);
      expect(stored.categories.single.name, _en.sourceScanned);
    });

    testWidgets('a paste with no dish shows the empty-paste copy and stays', (
      tester,
    ) async {
      // Arrange
      final pushed = <String>[];
      await _pump(tester, controller, pushed: pushed);
      await tester.enterText(find.byType(TextField), '45 ₪');
      await tester.pump();

      // Act
      await tester.tap(_analyse(_en));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.scanEmptyPaste), findsOneWidget);
      expect(pushed, isEmpty);
      expect(repository.storedMenus, isEmpty);
    });

    testWidgets('editing after the empty-paste copy clears it', (tester) async {
      // Arrange
      await _pump(tester, controller);
      await tester.enterText(find.byType(TextField), '45 ₪');
      await tester.pump();
      await tester.tap(_analyse(_en));
      await tester.pumpAndSettle();
      expect(find.text(_en.scanEmptyPaste), findsOneWidget);

      // Act
      await tester.enterText(find.byType(TextField), 'Steak');
      await tester.pump();

      // Assert
      expect(find.text(_en.scanEmptyPaste), findsNothing);
    });

    testWidgets('the empty-paste copy is in Hebrew under Locale(he)', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, controller, locale: const Locale('he'));
      await tester.enterText(find.byType(TextField), '45 ₪');
      await tester.pump();

      // Act
      await tester.tap(_analyse(_he));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.scanEmptyPaste), findsOneWidget);
    });
  });
}
