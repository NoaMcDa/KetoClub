import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/loader_colors.dart';
import 'package:ketoclub/widgets/keto_foods.dart';
import 'package:ketoclub/widgets/keto_loader.dart';
import 'package:ketoclub/widgets/skeletons.dart';

/// The English strings a test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings.
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps [child] in a localised, themed [MaterialApp], with reduced motion
/// when [reduceMotion].
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: page!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The centres of the orbit's three foods, in the order they are drawn.
List<Offset> _foodCentres(WidgetTester tester) => [
  for (final element in find.byType(KetoFoodIcon).evaluate())
    tester.getCenter(find.byWidget(element.widget)),
];

void main() {
  group('KetoOrbit (issue #450)', () {
    testWidgets('draws the steak, the egg and the lettuce, in that order', (
      tester,
    ) async {
      // Act
      await _pump(tester, const KetoOrbit());

      // Assert
      final foods = tester
          .widgetList<KetoFoodIcon>(find.byType(KetoFoodIcon))
          .map((icon) => icon.food)
          .toList();
      expect(foods, [KetoFood.steak, KetoFood.egg, KetoFood.lettuce]);
    });

    testWidgets("starts with the steak at twelve o'clock, the egg at four "
        'and the lettuce at eight', (tester) async {
      // Act
      await _pump(tester, const KetoOrbit(), reduceMotion: true);

      // Assert
      final centre = tester.getCenter(find.byType(KetoOrbit));
      final [steak, egg, lettuce] = _foodCentres(tester);
      expect(steak.dx, closeTo(centre.dx, 0.01));
      expect(steak.dy, lessThan(centre.dy));
      expect(egg.dx, greaterThan(centre.dx));
      expect(egg.dy, greaterThan(centre.dy));
      expect(lettuce.dx, lessThan(centre.dx));
      expect(lettuce.dy, closeTo(egg.dy, 0.01));
    });

    testWidgets('moves the foods round as time passes', (tester) async {
      // Arrange
      await _pump(tester, const KetoOrbit());
      final before = _foodCentres(tester);

      // Act: a quarter of a turn.
      await tester.pump(ketoOrbitPeriod ~/ 4);

      // Assert
      final after = _foodCentres(tester);
      expect(after.first, isNot(before.first));
      final centre = tester.getCenter(find.byType(KetoOrbit));
      // A quarter turn clockwise carries the steak from the top to the
      // right-hand side.
      expect(after.first.dx, greaterThan(centre.dx + 20));
    });

    testWidgets('keeps the foods on one ring as they go', (tester) async {
      // Arrange
      await _pump(tester, const KetoOrbit());
      await tester.pump(const Duration(milliseconds: 700));
      final centre = tester.getCenter(find.byType(KetoOrbit));

      // Assert: every food the same distance from the centre, give or
      // take its bob.
      final distances = [
        for (final food in _foodCentres(tester)) (food - centre).distance,
      ];
      for (final distance in distances) {
        expect(distance, closeTo(112 * 0.34, 2.5));
      }
    });

    testWidgets('holds still and schedules no frames under reduced '
        'motion', (tester) async {
      // Arrange
      await _pump(tester, const KetoOrbit(), reduceMotion: true);
      final before = _foodCentres(tester);

      // Act
      await tester.pump(ketoOrbitPeriod ~/ 3);

      // Assert
      expect(_foodCentres(tester), before);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('stops when reduced motion is turned on, and starts again '
        'when it is turned off', (tester) async {
      // Arrange
      await _pump(tester, const KetoOrbit());
      expect(tester.binding.hasScheduledFrame, isTrue);

      // Act
      await _pump(tester, const KetoOrbit(), reduceMotion: true);
      // The rebuild the switch causes, and the app's 200 ms theme
      // cross-fade (the helper builds a new theme each time), then none.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Act
      await _pump(tester, const KetoOrbit());

      // Assert
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('below 30px draws three dots, not the foods', (tester) async {
      // Act
      await _pump(tester, const KetoOrbit(size: 22));

      // Assert
      expect(find.byType(KetoFoodIcon), findsNothing);
      expect(
        find.descendant(
          of: find.byType(KetoOrbit),
          matching: find.byType(DecoratedBox),
        ),
        findsNWidgets(3),
      );
      expect(tester.getSize(find.byType(KetoOrbit)), const Size.square(22));
    });

    testWidgets('adds nothing to the semantics tree', (tester) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act
      await _pump(tester, const KetoOrbit());

      // Assert
      expect(tester.getSemantics(find.byType(KetoOrbit)).label, isEmpty);
      handle.dispose();
    });
  });

  group('KetoFoodIcon (issue #450)', () {
    for (final food in KetoFood.values) {
      testWidgets('paints the ${food.name} at the size it is given', (
        tester,
      ) async {
        // Act
        await _pump(tester, KetoFoodIcon(food, size: 44));

        // Assert
        expect(tester.getSize(find.byType(KetoFoodIcon)), const Size(44, 44));
        final paint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(KetoFoodIcon),
            matching: find.byType(CustomPaint),
          ),
        );
        final painter = paint.painter! as KetoFoodPainter;
        expect(painter.food, food);
        expect(painter.detailed, isTrue);
      });
    }

    testWidgets('leaves the small details out below 20px', (tester) async {
      // Act
      await _pump(tester, const KetoFoodIcon(KetoFood.lettuce, size: 14));

      // Assert
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(KetoFoodIcon),
          matching: find.byType(CustomPaint),
        ),
      );
      expect((paint.painter! as KetoFoodPainter).detailed, isFalse);
    });

    test('repaints only when what it paints changes', () {
      // Arrange
      const painter = KetoFoodPainter(
        food: KetoFood.egg,
        colors: LoaderColors.light(),
      );

      // Assert
      expect(
        painter.shouldRepaint(
          const KetoFoodPainter(
            food: KetoFood.egg,
            colors: LoaderColors.light(),
          ),
        ),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          const KetoFoodPainter(
            food: KetoFood.steak,
            colors: LoaderColors.light(),
          ),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          const KetoFoodPainter(
            food: KetoFood.egg,
            colors: LoaderColors.dark(),
          ),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          const KetoFoodPainter(
            food: KetoFood.egg,
            colors: LoaderColors.light(),
            detailed: false,
          ),
        ),
        isTrue,
      );
    });

    for (final theme in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets('paints every food under the ${theme.key} theme without '
          'an error', (tester) async {
        // Act
        await _pump(
          tester,
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KetoFoodIcon(KetoFood.steak),
              KetoFoodIcon(KetoFood.egg),
              KetoFoodIcon(KetoFood.lettuce),
              KetoFoodIcon(KetoFood.steak, size: 12),
              KetoFoodIcon(KetoFood.egg, size: 12),
              KetoFoodIcon(KetoFood.lettuce, size: 12),
            ],
          ),
          theme: theme.value,
        );

        // Assert
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('KetoLoader (issues #450, #451)', () {
    testWidgets('shows the orbit, the status and a line of kitchen talk', (
      tester,
    ) async {
      // Act
      await _pump(tester, const KetoLoader(status: 'Finding your location…'));

      // Assert
      expect(find.byType(KetoOrbit), findsOneWidget);
      expect(find.text('Finding your location…'), findsOneWidget);
      expect(find.text(_en.loadingTalkCarbs), findsOneWidget);
    });

    testWidgets('a screen reader hears the status once and none of the '
        'kitchen talk', (tester) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act
      await _pump(tester, const KetoLoader(status: 'Finding your location…'));

      // Assert
      expect(find.bySemanticsLabel('Finding your location…'), findsOneWidget);
      expect(find.bySemanticsLabel(_en.loadingTalkCarbs), findsNothing);
      final node = tester.getSemantics(find.byType(KetoLoader));
      expect(node.label, 'Finding your location…');
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('leaves the kitchen talk out when asked', (tester) async {
      // Act
      await _pump(tester, const KetoLoader(status: 'Loading', talk: false));

      // Assert
      expect(find.byType(KitchenTalk), findsNothing);
    });

    testWidgets('sizes the orbit as asked', (tester) async {
      // Act
      await _pump(tester, const KetoLoader(status: 'Loading', orbitSize: 88));

      // Assert
      expect(tester.getSize(find.byType(KetoOrbit)), const Size.square(88));
    });
  });

  group('KetoLoaderStrip (issue #451)', () {
    testWidgets('shows a small orbit beside the status and the kitchen '
        'talk, on a card', (tester) async {
      // Act
      await _pump(tester, const KetoLoaderStrip(status: 'Asking the AI…'));

      // Assert
      expect(
        tester.getSize(find.byType(KetoOrbit)),
        const Size.square(KetoLoaderStrip.orbitSize),
      );
      expect(find.byType(Card), findsOneWidget);
      final orbit = tester.getCenter(find.byType(KetoOrbit));
      final status = tester.getCenter(find.text('Asking the AI…'));
      expect(status.dx, greaterThan(orbit.dx));
      expect(find.byType(KitchenTalk), findsOneWidget);
    });

    testWidgets('is announced by its status alone', (tester) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act
      await _pump(tester, const KetoLoaderStrip(status: 'Asking the AI…'));

      // Assert
      expect(find.bySemanticsLabel('Asking the AI…'), findsOneWidget);
      expect(find.bySemanticsLabel(_en.loadingTalkCarbs), findsNothing);
      handle.dispose();
    });

    testWidgets('puts the orbit on the right in Hebrew', (tester) async {
      // Act
      await _pump(
        tester,
        const KetoLoaderStrip(status: 'שואלים את הבינה המלאכותית…'),
        locale: const Locale('he'),
      );

      // Assert
      final orbit = tester.getCenter(find.byType(KetoOrbit));
      final status = tester.getCenter(find.text('שואלים את הבינה המלאכותית…'));
      expect(orbit.dx, greaterThan(status.dx));
    });
  });

  group('KitchenTalk (issue #451)', () {
    testWidgets('moves to the next line every kitchenTalkPeriod and comes '
        'round again', (tester) async {
      // Arrange
      await _pump(tester, const KitchenTalk());
      final lines = KitchenTalk.linesOf(_en);
      expect(find.text(lines[0]), findsOneWidget);

      // Act + Assert: through every line and back to the first.
      for (var i = 1; i <= lines.length; i++) {
        await tester.pump(kitchenTalkPeriod);
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(lines[i % lines.length]), findsOneWidget);
      }
    });

    testWidgets('shows the first line and never changes under reduced '
        'motion', (tester) async {
      // Arrange
      await _pump(tester, const KitchenTalk(), reduceMotion: true);

      // Act
      await tester.pump(kitchenTalkPeriod * 3);

      // Assert
      expect(find.text(_en.loadingTalkCarbs), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('speaks Hebrew under Hebrew', (tester) async {
      // Act
      await _pump(tester, const KitchenTalk(), locale: const Locale('he'));

      // Assert
      expect(find.text(_he.loadingTalkCarbs), findsOneWidget);
    });

    test('every line is distinct, in both languages', () {
      // Assert
      for (final l10n in [_en, _he]) {
        final lines = KitchenTalk.linesOf(l10n);
        expect(lines.toSet(), hasLength(lines.length));
        expect(lines, everyElement(isNotEmpty));
      }
    });

    testWidgets('stops its timer when it leaves the screen', (tester) async {
      // Arrange
      await _pump(tester, const KitchenTalk());

      // Act: replace it; a timer still pending would fail the test.
      await _pump(tester, const SizedBox());
      await tester.pump(kitchenTalkPeriod * 2);

      // Assert
      expect(find.byType(KitchenTalk), findsNothing);
    });
  });

  group('EstimateProgress (issue #451)', () {
    /// The segments' colours, in order.
    List<Color?> segmentColors(WidgetTester tester) => [
      for (final box in tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      ))
        (box.decoration! as BoxDecoration).color,
    ];

    testWidgets('one segment per restaurant, the scored ones filled', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        const SizedBox(width: 300, child: EstimateProgress(done: 3, total: 12)),
      );
      await tester.pumpAndSettle();

      // Assert
      final colors = segmentColors(tester);
      expect(colors, hasLength(12));
      final accent = AppTheme.light().colorScheme.primary;
      expect(colors.take(3), everyElement(accent));
      expect(colors.skip(3), everyElement(isNot(accent)));
    });

    testWidgets('past maxSegments it is one bar at the right value', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        const SizedBox(
          width: 300,
          child: EstimateProgress(done: 30, total: 120),
        ),
      );

      // Assert
      expect(find.byType(AnimatedContainer), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
    });

    testWidgets('draws an empty bar for an empty run', (tester) async {
      // Act
      await _pump(
        tester,
        const SizedBox(width: 300, child: EstimateProgress(done: 0, total: 0)),
      );

      // Assert
      expect(find.byType(AnimatedContainer), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('skeleton sweep (issue #451)', () {
    /// The sweep's band positions inside the first skeleton block.
    double bandX(WidgetTester tester) => tester
        .widget<Align>(
          find
              .descendant(
                of: find.byType(DishCardSkeleton),
                matching: find.byType(Align),
              )
              .first,
        )
        .alignment
        .resolve(Directionality.of(tester.element(find.byType(Scaffold))))
        .x;

    testWidgets('a light sweeps across the placeholder blocks', (tester) async {
      // Arrange
      await _pump(
        tester,
        const SizedBox(width: 350, child: DishCardSkeleton()),
      );
      final start = bandX(tester);

      // Act: a third of the way through a sweep.
      await tester.pump(skeletonSweepPeriod ~/ 3);

      // Assert: it has moved toward the reading end.
      expect(bandX(tester), greaterThan(start));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('the sweep runs right to left in Hebrew', (tester) async {
      // Arrange
      await _pump(
        tester,
        const SizedBox(width: 350, child: DishCardSkeleton()),
        locale: const Locale('he'),
      );
      final start = bandX(tester);

      // Act
      await tester.pump(skeletonSweepPeriod ~/ 3);

      // Assert
      expect(bandX(tester), lessThan(start));
    });

    testWidgets('there is no sweep, and no frame, under reduced motion', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        const SizedBox(width: 350, child: DishCardSkeleton()),
        reduceMotion: true,
      );
      await tester.pump(skeletonSweepPeriod);

      // Assert
      expect(
        find.descendant(
          of: find.byType(DishCardSkeleton),
          matching: find.byType(Align),
        ),
        findsNothing,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
