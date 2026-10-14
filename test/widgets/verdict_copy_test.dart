// VerdictCopy (Banto, ALG-05, issue #347): one table of words for every
// state, wording and locale. Keto-only is today's copy verbatim, and no
// string produced for a profile with a strict entry ever says "safe" or
// "בטוח" — the sibling of failure_copy's no-shared-copy test.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/verdict_counts.dart';
import 'package:ketoclub/widgets/verdict_copy.dart';

/// "safe" as a word in English, "בטוח" (and its forms) anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

/// Every string VerdictCopy produces for [wording] in [l10n].
List<String> _everyString(AppLocalizations l10n, ProfileWording wording) {
  const counts = VerdictCounts(
    green: 3,
    yellow: 2,
    hiddenCarbYellow: 0,
    red: 1,
    ask: 4,
  );
  return <String>[
    for (final state in DishState.values) ...[
      VerdictCopy.badge(l10n, state, wording),
      VerdictCopy.tile(l10n, state, wording),
      VerdictCopy.legendDefinition(l10n, state, wording),
      for (final hebrew in <bool>[false, true])
        ?VerdictCopy.shareHeading(state, wording, hebrew: hebrew),
    ],
    for (final filter in MenuFilter.values)
      VerdictCopy.showing(l10n, filter, wording, total: 9),
    ...VerdictCopy.legendNotes(l10n),
    if (wording.usesStates) VerdictCopy.headerCounts(l10n, counts, wording),
    for (final hebrew in <bool>[false, true])
      ?VerdictCopy.shareFooter(wording, hebrew: hebrew),
  ];
}

/// An analysed dish for the evaluations below.
const AnalysedDish _analysed = AnalysedDish(
  dishId: 'd',
  name: 'Dish',
  verdict: DishVerdict.orderAsIs,
  why: 'why',
);

/// A suspected concern on [id] with an optional [question].
Concern _suspected(RestrictionId id, {String? question}) => Concern(
  restrictionId: id,
  source: ConcernSource.hidden,
  certainty: Certainty.suspected,
  tier: EvidenceTier.suspected,
  matchedText: 'sauce',
  waiterQuestion: question,
);

/// A dish named [name].
Dish _dish(String name) => Dish(
  id: 'd',
  name: name,
  description: '',
  price: 0,
  options: const <DishOption>[],
);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final he = lookupAppLocalizations(const Locale('he'));

  group('keto-only', () {
    test("the pill, tiles and showing labels are today's verbatim", () {
      const wording = ProfileWording.ketoOnly;
      for (final l10n in <AppLocalizations>[en, he]) {
        expect(
          VerdictCopy.badge(l10n, DishState.fits, wording),
          l10n.verdictOrderAsIs,
        );
        expect(
          VerdictCopy.badge(l10n, DishState.fitsWithChange, wording),
          l10n.verdictModifiable,
        );
        expect(
          VerdictCopy.badge(l10n, DishState.avoid, wording),
          l10n.verdictNonKeto,
        );
        expect(
          VerdictCopy.tile(l10n, DishState.fits, wording),
          l10n.tileGreenLabel,
        );
        expect(
          VerdictCopy.tile(l10n, DishState.fitsWithChange, wording),
          l10n.tileYellowLabel,
        );
        expect(
          VerdictCopy.tile(l10n, DishState.avoid, wording),
          l10n.tileRedLabel,
        );
        expect(
          VerdictCopy.showing(l10n, MenuFilter.greenOnly, wording, total: 9),
          l10n.menuShowingGreen,
        );
        expect(
          VerdictCopy.showing(l10n, MenuFilter.yellowOnly, wording, total: 9),
          l10n.menuShowingYellow,
        );
        expect(
          VerdictCopy.showing(l10n, MenuFilter.redOnly, wording, total: 9),
          l10n.menuShowingRed,
        );
        expect(
          VerdictCopy.showing(
            l10n,
            MenuFilter.greenAndYellow,
            wording,
            total: 9,
          ),
          l10n.menuShowingGreenAndYellow,
        );
        expect(
          VerdictCopy.showing(l10n, MenuFilter.all, wording, total: 9),
          l10n.menuShowingAll(9),
        );
        expect(
          VerdictCopy.showing(l10n, MenuFilter.askOnly, wording, total: 9),
          l10n.menuShowingAll(9),
        );
      }
    });

    test("the share headings are today's constants", () {
      const wording = ProfileWording.ketoOnly;
      expect(
        VerdictCopy.shareHeading(DishState.fits, wording, hebrew: false),
        shareGreenHeadingEn,
      );
      expect(
        VerdictCopy.shareHeading(DishState.fits, wording, hebrew: true),
        shareGreenHeadingHe,
      );
      expect(
        VerdictCopy.shareHeading(
          DishState.fitsWithChange,
          wording,
          hebrew: false,
        ),
        shareYellowHeadingEn,
      );
      expect(
        VerdictCopy.shareHeading(
          DishState.fitsWithChange,
          wording,
          hebrew: true,
        ),
        shareYellowHeadingHe,
      );
      expect(VerdictCopy.shareFooter(wording, hebrew: false), isNull);
    });
  });

  group('strict', () {
    test('a dish with nothing found reads "ask the restaurant"', () {
      expect(
        VerdictCopy.badge(en, DishState.fits, ProfileWording.strict),
        'No trigger found — ask the restaurant',
      );
      expect(
        VerdictCopy.badge(he, DishState.fits, ProfileWording.strict),
        contains('לשאול את המסעדה'),
      );
    });

    test('the legend carries the helper-tool sentence', () {
      for (final l10n in <AppLocalizations>[en, he]) {
        expect(
          VerdictCopy.legendNotes(l10n),
          contains(l10n.helperToolSentence),
        );
      }
    });

    test('the share text ends on a menu-text-only line', () {
      expect(
        VerdictCopy.shareFooter(ProfileWording.strict, hebrew: false),
        contains('Ask the restaurant'),
      );
      expect(
        VerdictCopy.shareFooter(ProfileWording.strict, hebrew: true),
        contains('לשאול את המסעדה'),
      );
    });

    test('the header counts name no score', () {
      const counts = VerdictCounts(
        green: 3,
        yellow: 2,
        hiddenCarbYellow: 0,
        red: 1,
        ask: 4,
      );
      expect(
        VerdictCopy.headerCounts(en, counts, ProfileWording.strict),
        '3 no trigger found · 2 with a change · 4 to ask',
      );
      expect(
        VerdictCopy.headerCounts(en, counts, ProfileWording.flexible),
        '3 fit · 2 with a change · 4 to ask',
      );
      // The owner's Hebrew wording for a strict profile (ALG-05).
      expect(
        VerdictCopy.headerCounts(he, counts, ProfileWording.strict),
        '3 ללא חשש · 2 עם שינוי · 4 לשאול',
      );
    });

    test('the Hebrew strict "fits" words are the owner\'s', () {
      // The tile says "ללא חשש"; the card's pill keeps the full sentence.
      expect(
        VerdictCopy.tile(he, DishState.fits, ProfileWording.strict),
        'ללא חשש',
      );
      expect(
        VerdictCopy.badge(he, DishState.fits, ProfileWording.strict),
        'לא נמצא חשש — לשאול את המסעדה',
      );
      expect(
        VerdictCopy.tile(en, DishState.fits, ProfileWording.strict),
        'No trigger found',
      );
    });
  });

  group('the "safe" ban', () {
    for (final wording in ProfileWording.values) {
      for (final (tag, l10n) in <(String, AppLocalizations)>[
        ('en', en),
        ('he', he),
      ]) {
        test('no ${wording.name} string in $tag says safe', () {
          final strings = _everyString(l10n, wording);
          expect(strings, isNotEmpty);
          for (final text in strings) {
            expect(text, isNot(matches(_safe)), reason: text);
          }
        });
      }
    }

    test('no fallback waiter question says safe', () {
      for (final id in RestrictionId.values) {
        for (final hebrew in <bool>[false, true]) {
          final question = VerdictCopy.askQuestionFor(id, hebrew: hebrew);
          expect(question, isNot(matches(_safe)), reason: question);
        }
      }
    });

    test('the four states never share a word in a state wording', () {
      for (final wording in <ProfileWording>[
        ProfileWording.flexible,
        ProfileWording.strict,
      ]) {
        for (final l10n in <AppLocalizations>[en, he]) {
          final badges = <String>{
            for (final state in DishState.values)
              VerdictCopy.badge(l10n, state, wording),
          };
          expect(badges, hasLength(DishState.values.length));
        }
      }
    });
  });

  group('waiter lines', () {
    test("fits with a change reads the evaluator's change", () {
      const evaluated = EvaluatedDish(
        dish: _analysed,
        concerns: <Concern>[],
        state: DishState.fitsWithChange,
        modification: 'Ask for it without tahini',
      );
      expect(
        VerdictCopy.waiterLine(evaluated, _dish('Salad')),
        'Ask for it without tahini',
      );
    });

    test("ask reads the first concern's own question", () {
      final evaluated = EvaluatedDish(
        dish: _analysed,
        concerns: <Concern>[
          _suspected(RestrictionId.peanuts, question: 'Any peanut oil?'),
        ],
        state: DishState.ask,
      );
      expect(
        VerdictCopy.waiterLine(evaluated, _dish('Cake')),
        'Any peanut oil?',
      );
    });

    test('ask without a question builds one in the dish language', () {
      final evaluated = EvaluatedDish(
        dish: _analysed,
        concerns: <Concern>[_suspected(RestrictionId.peanuts)],
        state: DishState.ask,
      );
      expect(
        VerdictCopy.waiterLine(evaluated, _dish('Nut cake')),
        contains('peanuts'),
      );
      expect(
        VerdictCopy.waiterLine(evaluated, _dish('עוגת אגוזים')),
        contains('בוטנים'),
      );
    });

    test('fits and avoid have no waiter line', () {
      for (final state in <DishState>[DishState.fits, DishState.avoid]) {
        final evaluated = EvaluatedDish(
          dish: _analysed,
          concerns: const <Concern>[],
          state: state,
        );
        expect(VerdictCopy.waiterLine(evaluated, _dish('Steak')), isNull);
      }
    });

    test('the restriction name follows the dish language', () {
      expect(
        VerdictCopy.restrictionName(RestrictionId.sesame, hebrew: true),
        'שומשום',
      );
      expect(
        VerdictCopy.restrictionName(RestrictionId.sesame, hebrew: false),
        'Sesame',
      );
    });
  });
}
