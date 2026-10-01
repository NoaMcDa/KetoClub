import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/photo_tile.dart';
import 'package:ketoclub/widgets/venue_card.dart';

/// The English strings this file reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

const Venue _venue = Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: 'ember-vine'),
  name: 'Ember & Vine',
  shortDescription: 'Charcoal grill and a serious salad list.',
  cuisineTags: <String>['steakhouse', 'grill'],
  isOnline: true,
  estimateMinutes: 12,
);

const VenueCardNumbers _llmNumbers = (
  score: 9.1,
  green: 9,
  yellow: 5,
  engine: LlmEngine(model: 'test-model'),
);

/// Numbers from the rules engine, which carry the [EngineChip] marker.
const VenueCardNumbers _rulesNumbers = (
  score: 6,
  green: 3,
  yellow: 2,
  engine: RulesEngine(reason: MenuAnalysisFailureReason.offline),
);

/// Pumps [card] in a themed, localised app at [locale], right-to-left
/// when [rtl], [width] wide when given, else the surface's full width.
Future<void> _pump(
  WidgetTester tester,
  VenueCard card, {
  Locale locale = const Locale('en'),
  bool rtl = false,
  double? width,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: width == null
                ? card
                : Align(
                    alignment: AlignmentDirectional.topStart,
                    child: SizedBox(width: width, child: card),
                  ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('VenueCard', () {
    testWidgets('shows name, blurb and "{cuisine} · {N} min" meta', (
      tester,
    ) async {
      // Act
      await _pump(tester, VenueCard(venue: _venue, onTap: () {}));

      // Assert
      expect(find.text('Ember & Vine'), findsOneWidget);
      expect(
        find.text('Charcoal grill and a serious salad list.'),
        findsOneWidget,
      );
      expect(
        find.text('Steakhouse · ${_en.venueCardMinutes(12)}'),
        findsOneWidget,
      );
    });

    testWidgets('without numbers shows no score and no counts (D13)', (
      tester,
    ) async {
      // Act
      await _pump(tester, VenueCard(venue: _venue, onTap: () {}));

      // Assert
      expect(find.byType(KetoScoreBadge), findsNothing);
      expect(find.text('9.1'), findsNothing);
      expect(find.textContaining('as-is'), findsNothing);
      expect(find.textContaining('with changes'), findsNothing);
      expect(find.byType(EngineChip), findsNothing);
    });

    testWidgets('with numbers shows the score and both counts', (tester) async {
      // Act
      await _pump(
        tester,
        VenueCard(venue: _venue, numbers: _llmNumbers, onTap: () {}),
      );

      // Assert
      expect(find.text('9.1'), findsOneWidget);
      expect(find.text(_en.venueCardGreenCount(9)), findsOneWidget);
      expect(find.text(_en.venueCardYellowCount(5)), findsOneWidget);
      // AI numbers carry no estimate marker.
      expect(find.byType(EngineChip), findsNothing);
    });

    testWidgets('rules-only numbers carry the engine label as the estimate '
        'marker', (tester) async {
      // Act
      await _pump(
        tester,
        VenueCard(
          venue: _venue,
          numbers: (
            score: 6,
            green: 3,
            yellow: 2,
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.offline,
            ),
          ),
          onTap: () {},
        ),
      );

      // Assert
      expect(find.byType(EngineChip), findsOneWidget);
      expect(find.text(_en.engineChipRules), findsOneWidget);
    });

    testWidgets('falls back to walking minutes from the distance, labelled '
        'as walking', (tester) async {
      // Act: 1 km at 5 km/h is 12 minutes.
      await _pump(
        tester,
        VenueCard(
          venue: const Venue(
            ref: VenueRef(source: MenuSource.wolt, platformId: 'x'),
            name: 'X',
            cuisineTags: <String>['sushi'],
          ),
          distanceKm: 1,
          onTap: () {},
        ),
      );

      // Assert
      expect(
        find.text('Sushi · ${_en.venueCardWalkMinutes(12)}'),
        findsOneWidget,
      );
    });

    testWidgets('omits the minutes when there is neither an estimate nor a '
        'distance', (tester) async {
      // Act
      await _pump(
        tester,
        VenueCard(
          venue: const Venue(
            ref: VenueRef(source: MenuSource.wolt, platformId: 'x'),
            name: 'X',
            cuisineTags: <String>['sushi'],
          ),
          onTap: () {},
        ),
      );

      // Assert
      expect(find.text('Sushi'), findsOneWidget);
      expect(find.textContaining('min'), findsNothing);
    });

    testWidgets('shows PhotoTile, which falls back to the placeholder '
        'gradient when there is no photo', (tester) async {
      // Act
      await _pump(tester, VenueCard(venue: _venue, onTap: () {}));

      // Assert
      expect(find.byType(PhotoTile), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('tapping calls onTap', (tester) async {
      // Arrange
      var taps = 0;
      await _pump(tester, VenueCard(venue: _venue, onTap: () => taps++));

      // Act
      await tester.tap(find.byType(VenueCard));

      // Assert
      expect(taps, 1);
    });

    testWidgets('announces name, open state and score as one label', (
      tester,
    ) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act
      await _pump(
        tester,
        VenueCard(venue: _venue, numbers: _llmNumbers, onTap: () {}),
      );

      // Assert
      final label = tester
          .getSemantics(find.byType(VenueCard))
          .getSemanticsData()
          .label;
      expect(label, contains('Ember & Vine'));
      expect(label, contains(_en.venueCardOpenNow));
      expect(label, contains(_en.menuKetoScoreSemanticLabel('9.1')));
      handle.dispose();
    });

    testWidgets('announces a closed venue as closed, with no score', (
      tester,
    ) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act
      await _pump(
        tester,
        VenueCard(
          venue: const Venue(
            ref: VenueRef(source: MenuSource.wolt, platformId: 'x'),
            name: 'X',
            isOnline: false,
          ),
          onTap: () {},
        ),
      );

      // Assert
      final label = tester
          .getSemantics(find.byType(VenueCard))
          .getSemanticsData()
          .label;
      expect(label, 'X, ${_en.venueCardClosed}');
      handle.dispose();
    });

    testWidgets('mirrors under right-to-left: the score sits left of the '
        'name', (tester) async {
      // Act
      await _pump(
        tester,
        VenueCard(venue: _venue, numbers: _llmNumbers, onTap: () {}),
        locale: const Locale('he'),
        rtl: true,
      );

      // Assert
      final name = tester.getCenter(find.text('Ember & Vine'));
      final score = tester.getCenter(find.byType(KetoScoreBadge));
      expect(score.dx, lessThan(name.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'build does not overflow at a 2x text scale on a narrow phone width '
      '(architecture.md §8.3)',
      (tester) async {
        // Arrange: a 340-wide surface, a small phone, at 2x text scale.
        tester.view.physicalSize = const Size(340, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Act
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: VenueCard(
                      venue: _venue,
                      numbers: _llmNumbers,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Assert
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets("without an aspect ratio the photo is the artboard's "
        "fixed-height banner, the card's full width", (tester) async {
      // Act: a 800-wide surface less the 20px padding each side.
      await _pump(tester, VenueCard(venue: _venue, onTap: () {}));

      // Assert
      expect(
        tester.getSize(find.byType(PhotoTile)),
        Size(tester.getSize(find.byType(VenueCard)).width, 118),
      );
    });

    testWidgets('with gridPhotoAspectRatio the photo is 3:2 at any width '
        '(issue #222)', (tester) async {
      for (final width in [240.0, 320.0, 400.0]) {
        // Act
        await _pump(
          tester,
          VenueCard(
            venue: _venue,
            photoAspectRatio: VenueCard.gridPhotoAspectRatio,
            onTap: () {},
          ),
          width: width,
        );

        // Assert
        final photo = tester.getSize(find.byType(PhotoTile));
        expect(photo.width, width);
        expect(photo.height, closeTo(width * 2 / 3, 0.01));
      }
    });

    testWidgets("draws on a Card with the theme's CardThemeData shape, "
        'the photo clipped to it (issue #222)', (tester) async {
      // Act
      await _pump(tester, VenueCard(venue: _venue, onTap: () {}));

      // Assert
      final card = tester.widget<Card>(
        find.descendant(
          of: find.byType(VenueCard),
          matching: find.byType(Card),
        ),
      );
      expect(card.margin, EdgeInsets.zero);
      expect(card.clipBehavior, Clip.antiAlias);
      expect(card.shape, isNull, reason: 'the theme supplies the shape');
      final material = tester.widget<Material>(
        find
            .descendant(of: find.byType(Card), matching: find.byType(Material))
            .first,
      );
      expect(material.shape, AppTheme.light().cardTheme.shape);
    });

    testWidgets('the ink well covers the whole card, photo included, and a '
        'hover lights it up (issue #222)', (tester) async {
      // Arrange
      await _pump(tester, VenueCard(venue: _venue, onTap: () {}));
      final inkWell = find.descendant(
        of: find.byType(VenueCard),
        matching: find.byType(InkWell),
      );

      // Assert: the ink well's box is the card's.
      expect(tester.getRect(inkWell), tester.getRect(find.byType(Card)));

      // Act: hover over the photo.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(PhotoTile)));
      await tester.pumpAndSettle();

      // Assert: the hover over the photo reaches the ink well, which
      // paints its highlight across the whole card.
      final ink = Material.of(tester.element(inkWell)) as RenderObject;
      expect(
        ink,
        paints..rect(
          rect: Offset.zero & tester.getSize(find.byType(Card)),
          color: AppTheme.light().hoverColor,
        ),
      );
    });

    testWidgets('in a row of grid tiles stretched to one height it lays out '
        'with no error, rules chip and all (issue #222)', (tester) async {
      // Act: the grid's IntrinsicHeight row asks the card for its
      // intrinsic height, which a LayoutBuilder could not answer.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final numbers in [_llmNumbers, _rulesNumbers])
                      Expanded(
                        child: VenueCard(
                          venue: _venue,
                          numbers: numbers,
                          photoAspectRatio: VenueCard.gridPhotoAspectRatio,
                          onTap: () {},
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(tester.takeException(), isNull);
      final cards = find.byType(VenueCard);
      expect(
        tester.getSize(cards.at(0)).height,
        tester.getSize(cards.at(1)).height,
      );
    });

    testWidgets('left-to-right keeps the score right of the name', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        VenueCard(venue: _venue, numbers: _llmNumbers, onTap: () {}),
      );

      // Assert
      final name = tester.getCenter(find.text('Ember & Vine'));
      final score = tester.getCenter(find.byType(KetoScoreBadge));
      expect(score.dx, greaterThan(name.dx));
    });
  });
}
