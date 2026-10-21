// The Recent tab under a Banto profile (issues #411 and #412): a row shows
// the four state counts in the profile's wording instead of the keto badge,
// asks for a re-check when the profile changed, offers "Did you ask the
// staff?" after the cache expired, and carries the "Worked for me" tag,
// chip and overflow. A keto-only profile, or a build without Banto, keeps
// today's row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/models/visit_dish.dart';
import 'package:ketoclub/screens/saved_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/state/confirmation_controller.dart';
import 'package:ketoclub/state/saved_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/visit_profile.dart';
import 'package:ketoclub/widgets/confirmation_sheet.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/verdict_copy.dart';
import 'package:ketoclub/widgets/worked_for_tag.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

const VenueRef _a = VenueRef(source: MenuSource.wolt, platformId: 'a');
const VenueRef _b = VenueRef(source: MenuSource.wolt, platformId: 'b');

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);
final DietaryProfile _lactose = DietaryProfile.empty.withEntry(
  RestrictionId.lactose,
);

/// The Hebrew-or-English state word of [state] for the profile's wording.
String _tile(AppLocalizations l10n, DishState state, bool strict) =>
    VerdictCopy.tile(
      l10n,
      state,
      strict ? ProfileWording.strict : ProfileWording.flexible,
    );

/// A visit to [ref] at [at] named [name], counted for [profile].
VisitEntry _visit(
  VenueRef ref,
  String name,
  DateTime at, {
  DietaryProfile? profile,
  bool strict = false,
  List<VisitDish>? dishes,
  List<String> workedFor = const <String>[],
}) => VisitEntry(
  ref: ref,
  name: name,
  firstOpenedAt: at,
  lastOpenedAt: at,
  openCount: 1,
  dishCount: 12,
  score: 7.5,
  greenCount: 5,
  yellowCount: 2,
  openedStrict: strict,
  fits: profile == null ? null : 4,
  withChange: profile == null ? null : 2,
  ask: profile == null ? null : 3,
  avoid: profile == null ? null : 1,
  profileFingerprint: profile == null ? null : profileFingerprintOf(profile),
  strictDishes: dishes,
  workedFor: workedFor,
);

const VisitDish _salad = VisitDish(
  dishId: 'salad',
  name: 'סלט חצילים',
  concerns: <VisitConcern>[
    VisitConcern(
      restrictionId: RestrictionId.sesame,
      source: ConcernSource.description,
    ),
  ],
);

final class _Harness {
  new(AppSettings settings)
    : settings = FakeSettingsStore(initial: settings),
      history = FakeVisitHistoryStore(FakeClock(DateTime(2026, 5, 12, 20)));

  final FakeSettingsStore settings;
  final FakeVisitHistoryStore history;
  final FakeMenuRepository repository = FakeMenuRepository();
  final FakeNotesStore notes = FakeNotesStore();
  late final FakeClock clock = FakeClock(DateTime(2026, 5, 12, 20));

  ConfirmationController confirmations(VenueRef ref) => ConfirmationController(
    ref: ref,
    repository: repository,
    settings: settings,
    history: history,
    notes: notes,
    clock: clock,
  );

  Future<void> pump(
    WidgetTester tester, {
    bool bantoMode = true,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: ChangeNotifierProvider<SavedController>(
          create: (_) => SavedController(repository, history, settings),
          child: SavedScreen(
            bantoMode: bantoMode,
            createConfirmations: confirmations,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  group('the counts on a row', () {
    testWidgets('a strict profile reads the four counts in the strict words, '
        'with no keto badge', (tester) async {
      // Arrange
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(_a, 'Hummus Bar', DateTime.utc(2026), profile: _sesame),
        );

      // Act
      await harness.pump(tester);

      // Assert
      expect(find.byType(KetoScoreBadge), findsNothing);
      expect(
        find.text(_en.savedStateCount(_tile(_en, DishState.fits, true), 4)),
        findsOneWidget,
      );
      expect(find.text('No trigger found: 4'), findsOneWidget);
      expect(find.text('With a change: 2'), findsOneWidget);
      expect(find.text('To ask: 3'), findsOneWidget);
      expect(find.text('Avoid: 1'), findsOneWidget);
      expect(find.text(_en.venueCardGreenCount(5)), findsNothing);
    });

    testWidgets('reads in Hebrew with the strict wording ללא חשש', (
      tester,
    ) async {
      // Arrange
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(_a, 'Hummus Bar', DateTime.utc(2026), profile: _sesame),
        );

      // Act
      await harness.pump(tester, locale: const Locale('he'));

      // Assert
      expect(find.text('ללא חשש: 4'), findsOneWidget);
      expect(
        find.text(_he.savedStateCount(_tile(_he, DishState.ask, true), 3)),
        findsOneWidget,
      );
      expect(find.byType(KetoScoreBadge), findsNothing);
    });

    testWidgets('a flexible profile says Fit, never the strict words', (
      tester,
    ) async {
      // Arrange
      final harness = _Harness(AppSettings(profile: _lactose))
        ..history.seed(
          _visit(_a, 'Hummus Bar', DateTime.utc(2026), profile: _lactose),
        );

      // Act
      await harness.pump(tester);

      // Assert
      expect(find.text('Fit: 4'), findsOneWidget);
      expect(find.text('No trigger found: 4'), findsNothing);
    });

    testWidgets('a changed profile shows the re-check hint and no numbers', (
      tester,
    ) async {
      // Arrange: counted for sesame, now sesame and lactose.
      final harness =
          _Harness(
              AppSettings(profile: _sesame.withEntry(RestrictionId.lactose)),
            )
            ..history.seed(
              _visit(_a, 'Hummus Bar', DateTime.utc(2026), profile: _sesame),
            );

      // Act
      await harness.pump(tester);

      // Assert
      expect(find.byKey(savedRecheckKey), findsOneWidget);
      expect(find.text(_en.savedRecheck), findsOneWidget);
      expect(find.byKey(savedStateCountsKey), findsNothing);
      expect(find.byType(KetoScoreBadge), findsNothing);
    });

    testWidgets("a keto-only profile keeps today's row", (tester) async {
      // Arrange
      final harness = _Harness(const AppSettings())
        ..history.seed(
          _visit(_a, 'Hummus Bar', DateTime.utc(2026), profile: _sesame),
        );

      // Act
      await harness.pump(tester);

      // Assert
      expect(find.byType(KetoScoreBadge), findsOneWidget);
      expect(find.text(_en.venueCardGreenCount(5)), findsOneWidget);
      expect(find.byKey(savedStateCountsKey), findsNothing);
      expect(find.byKey(savedRecheckKey), findsNothing);
      expect(find.byKey(savedWorkedChipKey), findsNothing);
    });

    testWidgets("a build without Banto keeps today's row under any "
        'profile', (tester) async {
      // Arrange
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(_a, 'Hummus Bar', DateTime.utc(2026), profile: _sesame),
        );

      // Act
      await harness.pump(tester, bantoMode: false);

      // Assert
      expect(find.byType(KetoScoreBadge), findsOneWidget);
      expect(find.byKey(savedStateCountsKey), findsNothing);
      expect(find.byKey(savedMoreKey(_a)), findsNothing);
    });
  });

  group('Did you ask the staff? past the cache', () {
    testWidgets('is offered for a strict visit with no cached menu, lists '
        'the kept dish, and records the answer', (tester) async {
      // Arrange: nothing is cached; the visit kept its strict dish.
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(
            _a,
            'Hummus Bar',
            DateTime.utc(2026),
            profile: _sesame,
            strict: true,
            dishes: const <VisitDish>[_salad],
          ),
        );
      await harness.pump(tester);
      expect(find.text(_en.savedNotOnDevice), findsOneWidget);

      // Act
      await tester.tap(find.text(_en.confirmPromptOpen));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.confirmUnavailable), findsNothing);
      expect(find.text('סלט חצילים'), findsOneWidget);

      // Act
      await tester.tap(
        find.byKey(confirmAnswerKey('salad', 0, ConfirmationAnswer.absent)),
      );
      await tester.pump();
      await tester.tap(find.byKey(confirmSaveKey));
      await tester.pumpAndSettle();

      // Assert: recorded, and the offer follows.
      expect(
        (await harness.history.read(_a))!.confirmations.single.dishId,
        'salad',
      );
      expect(find.text(_en.workedOffer), findsOneWidget);
    });

    testWidgets('is not offered for a visit that kept nothing and is not '
        'cached', (tester) async {
      // Arrange
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(_a, 'Hummus Bar', DateTime.utc(2026), strict: true),
        );

      // Act
      await harness.pump(tester);

      // Assert
      expect(find.text(_en.confirmPromptOpen), findsNothing);
    });
  });

  group('Worked for me', () {
    testWidgets('the offer marks the row, the tag shows, and the chip '
        'filters to it', (tester) async {
      // Arrange: two venues; only a has a strict visit to answer.
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(
            _a,
            'Hummus Bar',
            DateTime.utc(2026),
            profile: _sesame,
            strict: true,
            dishes: const <VisitDish>[_salad],
          ),
        )
        ..history.seed(
          _visit(_b, 'Falafel Place', DateTime.utc(2025), profile: _sesame),
        );
      await harness.pump(tester);
      expect(find.byKey(savedWorkedChipKey), findsNothing);
      expect(find.byKey(workedForTagKey), findsNothing);

      // Act: answer "no sesame" and take the offer.
      await tester.tap(find.text(_en.confirmPromptOpen));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(confirmAnswerKey('salad', 0, ConfirmationAnswer.absent)),
      );
      await tester.pump();
      await tester.tap(find.byKey(confirmSaveKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(workedOfferKey));
      await tester.pumpAndSettle();

      // Assert: stored, tagged, and the chip is there.
      expect((await harness.history.read(_a))!.workedFor, <String>['Me']);
      expect(find.byKey(workedForTagKey), findsOneWidget);
      expect(find.text(_en.workedChip), findsNWidgets(2)); // tag and chip
      expect(find.text('Falafel Place'), findsOneWidget);

      // Act
      await tester.tap(find.byKey(savedWorkedChipKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Hummus Bar'), findsOneWidget);
      expect(find.text('Falafel Place'), findsNothing);

      // Act: again, to show all.
      await tester.tap(find.byKey(savedWorkedChipKey));
      await tester.pumpAndSettle();
      expect(find.text('Falafel Place'), findsOneWidget);
    });

    testWidgets("the row's overflow marks and unmarks", (tester) async {
      // Arrange
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(_a, 'Hummus Bar', DateTime.utc(2026), profile: _sesame),
        );
      await harness.pump(tester);

      // Act
      await tester.tap(find.byKey(savedMoreKey(_a)));
      await tester.pumpAndSettle();
      expect(find.text(_en.workedMark), findsOneWidget);
      await tester.tap(find.byKey(savedWorkedToggleKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(workedForTagKey), findsOneWidget);
      expect((await harness.history.read(_a))!.workedFor, <String>['Me']);

      // Act
      await tester.tap(find.byKey(savedMoreKey(_a)));
      await tester.pumpAndSettle();
      expect(find.text(_en.workedUnmark), findsOneWidget);
      await tester.tap(find.byKey(savedWorkedToggleKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(workedForTagKey), findsNothing);
      expect(find.byKey(savedWorkedChipKey), findsNothing);
      expect((await harness.history.read(_a))!.workedFor, isEmpty);
    });

    testWidgets('a group reads "Worked for Noa, Dana"', (tester) async {
      // Arrange
      final dana = NamedProfile(id: 'dana', name: 'Dana', profile: _lactose);
      final union = _sesame.withEntry(RestrictionId.lactose);
      final harness =
          _Harness(
              AppSettings(
                profile: _sesame,
                primaryProfileName: 'Noa',
                otherProfiles: <NamedProfile>[dana],
                activeProfileIds: const <String>[
                  NamedProfile.primaryId,
                  'dana',
                ],
              ),
            )
            ..history.seed(
              _visit(
                _a,
                'Hummus Bar',
                DateTime.utc(2026),
                profile: union,
                workedFor: const <String>['Noa', 'Dana'],
              ),
            );

      // Act
      await harness.pump(tester);

      // Assert
      expect(find.text(_en.workedTagNames('Noa, Dana')), findsOneWidget);
    });

    testWidgets('the tag and chip read in Hebrew, never בטוח', (tester) async {
      // Arrange
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(
            _a,
            'Hummus Bar',
            DateTime.utc(2026),
            profile: _sesame,
            workedFor: const <String>['Me'],
          ),
        );

      // Act
      await harness.pump(tester, locale: const Locale('he'));

      // Assert
      expect(find.text(_he.workedChip), findsNWidgets(2));
      expect(find.textContaining('בטוח'), findsNothing);
    });

    testWidgets('a keto build shows no mark even when one is stored', (
      tester,
    ) async {
      // Arrange
      final harness = _Harness(AppSettings(profile: _sesame))
        ..history.seed(
          _visit(
            _a,
            'Hummus Bar',
            DateTime.utc(2026),
            workedFor: const <String>['Me'],
          ),
        );

      // Act
      await harness.pump(tester, bantoMode: false);

      // Assert
      expect(find.byKey(workedForTagKey), findsNothing);
      expect(find.byKey(savedWorkedChipKey), findsNothing);
    });
  });
}
