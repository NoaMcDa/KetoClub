import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:ketoclub/widgets/venue_card.dart';

/// Pumps [child] inside a [MaterialApp] and a [Scaffold], the shape every
/// widget test in `test/widgets/` uses. [theme] defaults to null, the
/// bare-[MaterialApp] shape most of this file's tests use.
Future<void> _pump(WidgetTester tester, Widget child, {ThemeData? theme}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: child),
    ),
  );
}

/// The first [DecoratedBox]'s fill colour under [finder] — every skeleton
/// in this file draws its blocks that way (issue #63).
Color _firstBlockColor(WidgetTester tester, Finder finder) {
  final decoration =
      tester
              .widget<DecoratedBox>(
                find
                    .descendant(of: finder, matching: find.byType(DecoratedBox))
                    .first,
              )
              .decoration
          as BoxDecoration;
  return decoration.color!;
}

void main() {
  group('VenueCardSkeleton', () {
    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets('build renders on the ${entry.key} theme with no error', (
        tester,
      ) async {
        // Act
        await _pump(tester, const VenueCardSkeleton(), theme: entry.value);

        // Assert: it builds, and its photo block reads the theme's own
        // NeutralSurfaces.surface2 — never a literal hex.
        expect(tester.takeException(), isNull);
        expect(find.byType(VenueCardSkeleton), findsOneWidget);
        final neutral = entry.value.extension<NeutralSurfaces>()!;
        expect(
          _firstBlockColor(tester, find.byType(VenueCardSkeleton)),
          neutral.surface2,
        );
      });
    }

    testWidgets(
      "build's photo block is VenueCard.photoHeight tall, matching the "
      'real card it stands in for',
      (tester) async {
        // Act
        await _pump(tester, const VenueCardSkeleton());

        // Assert
        final block = tester.widget<SizedBox>(find.byType(SizedBox).first);
        expect(block.height, VenueCard.photoHeight);
      },
    );

    testWidgets("build's photo block keeps photoAspectRatio when given, as "
        'the grid card it stands in for does (issue #222)', (tester) async {
      // Act
      await _pump(
        tester,
        const Center(
          child: SizedBox(
            width: 300,
            child: VenueCardSkeleton(
              photoAspectRatio: VenueCard.gridPhotoAspectRatio,
            ),
          ),
        ),
      );

      // Assert
      final block = tester.getSize(
        find
            .descendant(
              of: find.byType(AspectRatio),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(block, const Size(300, 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('build draws on the same card surface as VenueCard', (
      tester,
    ) async {
      // Act
      await _pump(tester, const VenueCardSkeleton());

      // Assert
      expect(
        find.descendant(
          of: find.byType(VenueCardSkeleton),
          matching: find.byType(Card),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('a run of skeletons wrapped in one Semantics label reads as that '
      'label alone, since every skeleton excludes its own semantics — a '
      'screen reader hears the loading announcement once, not once per '
      'card', (tester) async {
    // Act
    await _pump(
      tester,
      Semantics(
        liveRegion: true,
        label: 'Loading',
        child: const Column(
          children: [
            VenueCardSkeleton(),
            DishCardSkeleton(),
            SavedEntrySkeleton(),
          ],
        ),
      ),
    );

    // Assert
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Column),
        matching: find.byType(ExcludeSemantics),
      ),
      findsNWidgets(3),
    );
  });
}
