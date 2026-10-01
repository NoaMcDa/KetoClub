import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/widgets/menu_filters_row.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the Locale('he') case.
final AppLocalizations _he = AppLocalizationsHe();

/// Stands in for the search field, budget and legend behind the row.
const Key _panelKey = Key('panel');

/// Pumps [child] inside a localised [MaterialApp] and a [Scaffold], the
/// shape every widget test in `test/widgets/` uses.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: child),
    ),
  );
}

/// A row that toggles itself, the way the menu screen drives it, around
/// a text field whose typed text must survive a collapse.
class _Harness extends StatefulWidget {
  const new();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return MenuFiltersRow(
      expanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      child: const TextField(key: _panelKey),
    );
  }
}

void main() {
  group('MenuFiltersRow', () {
    testWidgets('collapsed: shows the Filters label and hides its child', (
      tester,
    ) async {
      // Arrange & Act
      await _pump(
        tester,
        MenuFiltersRow(
          expanded: false,
          onToggle: () {},
          child: const SizedBox(key: _panelKey, height: 40),
        ),
      );

      // Assert
      expect(find.text(_en.menuFilters), findsOneWidget);
      expect(find.byKey(_panelKey), findsNothing);
    });

    testWidgets('expanded: shows its child below the label', (tester) async {
      // Arrange & Act
      await _pump(
        tester,
        MenuFiltersRow(
          expanded: true,
          onToggle: () {},
          child: const SizedBox(key: _panelKey, height: 40),
        ),
      );

      // Assert
      expect(find.byKey(_panelKey), findsOneWidget);
      final label = tester.getRect(find.text(_en.menuFilters));
      final panel = tester.getRect(find.byKey(_panelKey));
      expect(panel.top, greaterThanOrEqualTo(label.bottom));
    });

    testWidgets('tapping the row calls onToggle', (tester) async {
      // Arrange
      var toggles = 0;
      await _pump(
        tester,
        MenuFiltersRow(
          expanded: false,
          onToggle: () => toggles++,
          child: const SizedBox.shrink(),
        ),
      );

      // Act
      await tester.tap(find.text(_en.menuFilters));

      // Assert
      expect(toggles, 1);
    });

    testWidgets('names how many filters are active', (tester) async {
      // Arrange & Act
      await _pump(
        tester,
        MenuFiltersRow(
          expanded: false,
          activeCount: 2,
          onToggle: () {},
          child: const SizedBox.shrink(),
        ),
      );

      // Assert
      expect(find.text(_en.menuFiltersActive(2)), findsOneWidget);
      expect(find.text(_en.menuFilters), findsNothing);
    });

    testWidgets('keeps text typed into its child across a collapse', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, const _Harness());
      await tester.tap(find.text(_en.menuFilters));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_panelKey), 'steak');

      // Act: collapse, then expand again.
      await tester.tap(find.text(_en.menuFilters));
      await tester.pumpAndSettle();
      expect(find.byKey(_panelKey), findsNothing);
      await tester.tap(find.text(_en.menuFilters));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('steak'), findsOneWidget);
    });

    testWidgets('announces itself as a button with its expanded state', (
      tester,
    ) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act
      await _pump(
        tester,
        MenuFiltersRow(
          expanded: true,
          activeCount: 1,
          onToggle: () {},
          child: const SizedBox.shrink(),
        ),
      );

      // Assert
      expect(tester.getSemantics(find.byType(MenuFiltersRow)), isNot(isNull));
      expect(find.bySemanticsLabel(_en.menuFiltersActive(1)), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel(_en.menuFiltersActive(1))),
        matchesSemantics(
          label: _en.menuFiltersActive(1),
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('reads in Hebrew under Locale("he")', (tester) async {
      // Arrange & Act
      await _pump(
        tester,
        MenuFiltersRow(
          expanded: false,
          activeCount: 1,
          onToggle: () {},
          child: const SizedBox.shrink(),
        ),
        locale: const Locale('he'),
      );

      // Assert
      expect(find.text(_he.menuFiltersActive(1)), findsOneWidget);
      expect(find.bySemanticsLabel(_he.menuFiltersActive(1)), findsOneWidget);
    });
  });
}
