import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/widgets/status_badge.dart';

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

void main() {
  group('StatusBadge', () {
    testWidgets('build renders an icon alongside the label for every verdict', (
      tester,
    ) async {
      for (final verdict in DishVerdict.values) {
        // Arrange
        await _pump(tester, StatusBadge(verdict: verdict));

        // Act
        final icons = find.byType(Icon);
        final texts = find.byType(Text);

        // Assert: the icon is never the only signal — a colour-blind user
        // must be able to read the same verdict from the text alone.
        expect(icons, findsOneWidget);
        expect(texts, findsOneWidget);
      }
    });

    testWidgets(
      'build shows the verdictOrderAsIs label, uppercased, for orderAsIs',
      (tester) async {
        // Arrange
        await _pump(tester, const StatusBadge(verdict: DishVerdict.orderAsIs));

        // Act & Assert: the pill is uppercase per the artboard's `.pill`
        // class, but the label text itself stays sentence-case in the
        // ARB file — only the display transforms it.
        expect(find.text('ORDER AS-IS'), findsOneWidget);
      },
    );

    testWidgets(
      'build shows the verdictModifiable label, uppercased, for modifiable',
      (tester) async {
        // Arrange
        await _pump(tester, const StatusBadge(verdict: DishVerdict.modifiable));

        // Act & Assert
        expect(find.text('ORDER WITH A CHANGE'), findsOneWidget);
      },
    );

    testWidgets(
      'build shows the verdictNonKeto label, uppercased, for nonKeto',
      (tester) async {
        // Arrange
        await _pump(tester, const StatusBadge(verdict: DishVerdict.nonKeto));

        // Act & Assert
        expect(find.text('NOT KETO'), findsOneWidget);
      },
    );

    testWidgets('build shows the Hebrew label in the he locale', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        const StatusBadge(verdict: DishVerdict.nonKeto),
        locale: const Locale('he'),
      );

      // Act & Assert: Hebrew has no letter case, so the ARB text is shown
      // verbatim.
      expect(find.text('לא קטוגני'), findsOneWidget);
    });

    testWidgets('build carries a Semantics label naming the verdict for screen '
        'readers', (tester) async {
      // Arrange
      await _pump(tester, const StatusBadge(verdict: DishVerdict.modifiable));

      // Act & Assert
      expect(
        find.bySemanticsLabel('Verdict: Order with a change'),
        findsOneWidget,
      );
    });

    testWidgets(
      'build does not overflow at a 2x text scale (architecture.md §8.3)',
      (tester) async {
        for (final verdict in DishVerdict.values) {
          // Arrange: a narrow, phone-width host so a doubled label has the
          // least room to grow into — the realistic worst case for the
          // large-text audit, not the wide default test surface.
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: SizedBox(
                      width: 160,
                      child: StatusBadge(verdict: verdict),
                    ),
                  ),
                ),
              ),
            ),
          );

          // Assert: no RenderFlex overflow exception was thrown.
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('build paints the pill background from VerdictColors.pill, not '
        'VerdictColors.rail', (tester) async {
      // Arrange: green and amber render their pill on the loud base
      // colour; red renders its pill on its own tint instead — a
      // deliberate difference the artboard makes (VerdictTone's own doc
      // comment explains why).
      await _pump(tester, const StatusBadge(verdict: DishVerdict.nonKeto));

      // Act
      final decoration =
          tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
              as BoxDecoration;
      final tone = VerdictColors.light().red;

      // Assert
      expect(decoration.color, tone.pill);
      expect(decoration.color, isNot(tone.rail));
    });
  });
}
