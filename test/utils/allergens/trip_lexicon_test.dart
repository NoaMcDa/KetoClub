// Trip mode's local hidden-ingredient lexicons (Banto, ALG-13, issue #355):
// the data's shape and sources, every term compiling and matching, and the
// evaluator reading a destination's terms as suspected triggers only while
// a trip is active — in English and, for Israel, in Hebrew — without ever
// touching keto.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/custom_terms.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/trip_lexicon.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

/// A source citation: file 11 or 12, a section, an optional subsection.
final RegExp _source = RegExp(r'^1[12] §(\d+)(\.\d+)?$');

/// A dish named [name].
Dish _dish(String name, {String description = ''}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: const <DishOption>[],
);

/// [dish] analysed with [verdict].
AnalysedDish _analysed(
  Dish dish, {
  DishVerdict verdict = DishVerdict.orderAsIs,
  String? modification,
}) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: verdict,
  why: 'Reason',
  modification: modification,
);

/// A profile holding [ids], in order.
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

/// [dish] evaluated as green for [profile], with [trip].
EvaluatedDish _evaluate(
  Dish dish,
  DietaryProfile profile, {
  TripDestination? trip,
}) => ProfileEvaluator.evaluate(_analysed(dish), dish, profile, trip: trip);

/// Whether the documentation file [file] (11 or 12) has the section
/// [section] (`8`) or subsection (`8.2`) as a heading.
bool _hasSection(String file, String section) {
  final name = file == '11'
      ? '11_hidden_allergen_sources.md'
      : '12_israeli_and_us_menu_lexicon.md';
  final text = File('allergen app documentation/$name').readAsStringSync();
  final heading = section.contains('.')
      ? RegExp('^### ${RegExp.escape(section)}[ ,]', multiLine: true)
      : RegExp('^## ${RegExp.escape(section)}\\. ', multiLine: true);
  return heading.hasMatch(text);
}

void main() {
  group('the data', () {
    test('every destination has a lexicon, and only those', () {
      expect(tripLexicon.keys.toSet(), TripDestination.values.toSet());
      for (final destination in TripDestination.values) {
        expect(
          TripLexicon.entriesFor(destination),
          hasLength(greaterThanOrEqualTo(8)),
          reason: destination.name,
        );
      }
    });

    test('every entry has terms, glosses, restrictions and a source that '
        'names a real section of file 11 or 12', () {
      for (final MapEntry(key: destination, value: entries)
          in tripLexicon.entries) {
        for (final entry in entries) {
          final where = '${destination.name}: $entry';
          expect(entry.terms, isNotEmpty, reason: where);
          expect(entry.hides, isNotEmpty, reason: where);
          expect(entry.glossEn.trim(), isNotEmpty, reason: where);
          expect(entry.glossHe.trim(), isNotEmpty, reason: where);
          expect(entry.hides, isNot(contains(RestrictionId.keto)));
          final match = _source.firstMatch(entry.source);
          expect(match, isNotNull, reason: '$where cites ${entry.source}');
          final file = entry.source.substring(0, 2);
          final section = entry.source.split('§').last;
          expect(
            _hasSection(file, section),
            isTrue,
            reason: '$where cites ${entry.source}, which has no heading',
          );
        }
      }
    });

    test('no term is listed twice within a destination', () {
      for (final destination in TripDestination.values) {
        final seen = <String>{};
        for (final entry in TripLexicon.entriesFor(destination)) {
          for (final term in entry.terms) {
            expect(
              seen.add(AllergenMatcher.matchText(term)),
              isTrue,
              reason: '${destination.name}: $term',
            );
          }
        }
      }
    });

    test('no term uses a script the matcher cannot read: Latin-1 or Hebrew '
        'only, and no ß', () {
      final readable = RegExp(r"^[ -ÿ֐-׿'’-]+$");
      for (final destination in TripDestination.values) {
        for (final entry in TripLexicon.entriesFor(destination)) {
          for (final term in entry.terms) {
            expect(readable.hasMatch(term), isTrue, reason: term);
            expect(term.contains('ß'), isFalse, reason: term);
          }
        }
      }
    });

    test('the glosses never call anything safe', () {
      final safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);
      for (final destination in TripDestination.values) {
        for (final entry in TripLexicon.entriesFor(destination)) {
          expect(safe.hasMatch(entry.glossEn), isFalse, reason: '$entry');
          expect(safe.hasMatch(entry.glossHe), isFalse, reason: '$entry');
        }
      }
    });

    test('the fact-checked glosses keep their hedges (checked '
        '2026-10-19; file 12 §8)', () {
      String gloss(TripDestination destination, String term) =>
          TripLexicon.entriesFor(destination)
              .singleWhere((entry) => entry.terms.contains(term))
              .glossEn;

      // Kelp-only dashi exists: "usually", never "made from".
      expect(gloss(TripDestination.japan, 'dashi'), contains('usually'));
      // Tamari can be brewed without wheat: "standard" soy sauce.
      expect(gloss(TripDestination.japan, 'shoyu'), startsWith('Standard'));
      // One published recipe is no "many".
      expect(gloss(TripDestination.israel, 'falafel'), contains('some'));
      // Osem lists soy; export packs print it as "may contain".
      expect(gloss(TripDestination.israel, 'Bamba'), contains('soy'));
      expect(gloss(TripDestination.germany, 'Senf'), isNot(contains('every')));
    });

    test('restrictions add what follows by definition', () {
      const dashi = TripLexiconEntry(
        terms: <String>['dashi'],
        hides: <RestrictionId>[RestrictionId.fish],
        glossEn: 'x',
        glossHe: 'x',
        source: '11 §8.1',
      );
      expect(dashi.restrictions, <RestrictionId>[
        RestrictionId.fish,
        RestrictionId.vegan,
        RestrictionId.vegetarian,
      ]);
      const pesto = TripLexiconEntry(
        terms: <String>['pesto'],
        hides: <RestrictionId>[RestrictionId.treeNuts, RestrictionId.milk],
        glossEn: 'x',
        glossHe: 'x',
        source: '12 §5',
      );
      expect(pesto.restrictions, <RestrictionId>[
        RestrictionId.treeNuts,
        RestrictionId.milk,
        RestrictionId.lactose,
        RestrictionId.vegan,
      ]);
      const mustard = TripLexiconEntry(
        terms: <String>['Senf'],
        hides: <RestrictionId>[RestrictionId.mustard],
        glossEn: 'x',
        glossHe: 'x',
        source: '12 §8.6',
      );
      expect(mustard.restrictions, <RestrictionId>[RestrictionId.mustard]);
      // Shellfish is not kosher by definition (#342); fish is.
      const scampi = TripLexiconEntry(
        terms: <String>['scampi'],
        hides: <RestrictionId>[RestrictionId.crustaceans],
        glossEn: 'x',
        glossHe: 'x',
        source: '11 §9.1',
      );
      expect(scampi.restrictions, <RestrictionId>[
        RestrictionId.crustaceans,
        RestrictionId.vegan,
        RestrictionId.vegetarian,
        RestrictionId.kosher,
      ]);
      expect(dashi.restrictions, isNot(contains(RestrictionId.kosher)));
    });
  });

  group('the vocabulary', () {
    test('every term of every entry matches itself, for every restriction '
        'it hides, as a suspected hidden trigger', () {
      for (final destination in TripDestination.values) {
        final vocabulary = TripLexicon.vocabularyFor(destination);
        for (final entry in TripLexicon.entriesFor(destination)) {
          for (final term in entry.terms) {
            final hits = AllergenMatcher.findWith(term, vocabulary);
            expect(
              <RestrictionId>{for (final hit in hits) hit.id},
              containsAll(entry.restrictions),
              reason: '${destination.name}: $term',
            );
            for (final hit in hits) {
              expect(hit.certainty, TriggerCertainty.suspected);
              expect(hit.hidden, isTrue);
            }
          }
        }
      }
    });

    test('is the same map every time, so the matcher compiles it once', () {
      expect(
        identical(
          TripLexicon.vocabularyFor(TripDestination.japan),
          TripLexicon.vocabularyFor(TripDestination.japan),
        ),
        isTrue,
      );
      final own = customTermVocabulary(const <String>['kiwi']);
      expect(
        identical(
          TripLexicon.withTrip(own, TripDestination.japan),
          TripLexicon.withTrip(own, TripDestination.japan),
        ),
        isTrue,
      );
    });

    test("withTrip without a trip is the user's own vocabulary itself", () {
      final own = customTermVocabulary(const <String>['kiwi']);
      expect(identical(TripLexicon.withTrip(own, null), own), isTrue);
    });

    test("withTrip keeps the user's own words beside the destination's", () {
      final merged = TripLexicon.withTrip(
        customTermVocabulary(const <String>['kiwi']),
        TripDestination.germany,
      );
      expect(merged[RestrictionId.custom]?.directEn, contains('kiwi'));
      expect(
        merged[RestrictionId.mustard]?.hiddenEn.map((t) => t.term),
        contains('Senf'),
      );
    });

    test(
      'Hebrew terms go to the Hebrew list and take a grammatical prefix',
      () {
        final vocabulary = TripLexicon.vocabularyFor(TripDestination.israel);
        expect(
          vocabulary[RestrictionId.fish]?.hiddenHe.map((t) => t.term),
          contains('חריימה'),
        );
        expect(
          AllergenMatcher.findWith('דג בחריימה', vocabulary).map((h) => h.id),
          contains(RestrictionId.fish),
        );
        expect(
          AllergenMatcher.findWith('ושקדי מרק', vocabulary).map((h) => h.id),
          containsAll(<RestrictionId>[
            RestrictionId.wheat,
            RestrictionId.gluten,
          ]),
        );
      },
    );
  });

  group('the evaluator, while a trip is active', () {
    final cases = <({TripDestination trip, String dish, RestrictionId id})>[
      (trip: TripDestination.japan, dish: 'Yakisoba', id: RestrictionId.wheat),
      (
        trip: TripDestination.japan,
        dish: 'Spinach goma ae',
        id: RestrictionId.sesame,
      ),
      (
        trip: TripDestination.japan,
        dish: 'Okonomiyaki',
        id: RestrictionId.fish,
      ),
      (
        trip: TripDestination.germany,
        dish: 'Rinderroulade mit Rotkohl',
        id: RestrictionId.mustard,
      ),
      (
        trip: TripDestination.germany,
        dish: 'Bratkartoffeln mit Senf',
        id: RestrictionId.mustard,
      ),
      (
        trip: TripDestination.germany,
        dish: 'Sellerie-Schnitzel',
        id: RestrictionId.celery,
      ),
      (
        trip: TripDestination.france,
        dish: 'Lapin à la moutarde',
        id: RestrictionId.mustard,
      ),
      (
        trip: TripDestination.spain,
        dish: 'Pollo con salsa de mostaza',
        id: RestrictionId.mustard,
      ),
      (trip: TripDestination.spain, dish: 'Croquetas', id: RestrictionId.milk),
      (
        trip: TripDestination.italy,
        dish: 'Vitello tonnato',
        id: RestrictionId.fish,
      ),
      (
        trip: TripDestination.unitedKingdom,
        dish: 'Marmite on toast',
        id: RestrictionId.celery,
      ),
      (
        trip: TripDestination.unitedStates,
        dish: 'Chicken enchiladas',
        id: RestrictionId.peanuts,
      ),
      (
        trip: TripDestination.israel,
        dish: 'Kubbeh soup',
        id: RestrictionId.wheat,
      ),
    ];

    for (final (:trip, :dish, :id) in cases) {
      test('"$dish" in ${trip.name} asks about ${id.name}; with no trip it '
          'fits', () {
        final profile = _profile(<RestrictionId>[id]);
        final menuDish = _dish(dish);

        final without = _evaluate(menuDish, profile);
        final withTrip = _evaluate(menuDish, profile, trip: trip);

        expect(without.state, DishState.fits, reason: 'no trip');
        expect(without.concerns, isEmpty);
        expect(withTrip.state, DishState.ask);
        final concern = withTrip.concerns.single;
        expect(concern.restrictionId, id);
        expect(concern.certainty, Certainty.suspected);
        expect(concern.source, ConcernSource.hidden);
        expect(concern.waiterQuestion, isNotNull);
      });
    }

    test("another destination's terms are not read", () {
      final profile = _profile(<RestrictionId>[RestrictionId.mustard]);
      expect(
        _evaluate(
          _dish('Bratkartoffeln mit Senf'),
          profile,
          trip: TripDestination.japan,
        ).state,
        DishState.fits,
      );
    });

    test('a flexible entry lists the suspicion and moves nothing', () {
      final result = _evaluate(
        _dish('Miso soup with dashi'),
        _profile(<RestrictionId>[RestrictionId.vegetarian]),
        trip: TripDestination.japan,
      );
      expect(result.state, DishState.fits);
      expect(
        result.concerns.map((c) => c.restrictionId),
        contains(RestrictionId.vegetarian),
      );
    });

    test('a stronger finding from the base vocabulary is kept', () {
      final result = _evaluate(
        _dish('Soy sauce glazed salmon'),
        _profile(<RestrictionId>[RestrictionId.soy]),
        trip: TripDestination.japan,
      );
      expect(result.state, DishState.avoid);
      expect(result.concerns.single.certainty, isNot(Certainty.suspected));
    });

    test("the model's ingredients are read for the trip terms too", () {
      final dish = _dish('Chef special');
      const ingredient = ExtractedIngredient(
        name: 'gomadare',
        certainty: Certainty.stated,
        role: ComponentRole.sauce,
      );
      final analysed = AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'Reason',
        ingredients: const <ExtractedIngredient>[ingredient],
      );
      final profile = _profile(<RestrictionId>[RestrictionId.sesame]);

      expect(
        ProfileEvaluator.evaluate(analysed, dish, profile).state,
        DishState.fits,
      );
      final withTrip = ProfileEvaluator.evaluate(
        analysed,
        dish,
        profile,
        trip: TripDestination.japan,
      );
      expect(withTrip.state, DishState.ask);
      expect(withTrip.concerns.single.source, ConcernSource.model);
    });

    test('a group evaluation reads the trip for every person', () {
      final dish = _dish('Yakisoba');
      final group = GroupEvaluator.evaluate(
        _analysed(dish),
        dish,
        <NamedProfile>[
          NamedProfile(
            id: NamedProfile.primaryId,
            name: '',
            profile: _profile(<RestrictionId>[RestrictionId.wheat]),
          ),
          NamedProfile(
            id: 'p1',
            name: 'Dana',
            profile: _profile(<RestrictionId>[RestrictionId.soy]),
          ),
        ],
        trip: TripDestination.japan,
      );
      expect(group.combined.state, DishState.ask);
      expect(
        group.people.map((p) => p.evaluated.state),
        everyElement(DishState.ask),
      );
    });
  });

  group('trip mode never changes keto', () {
    test('a keto-only profile evaluates identically with and without a '
        'trip, for every destination', () {
      final dishes = <(Dish, AnalysedDish)>[
        for (final (name, verdict) in <(String, DishVerdict)>[
          ('Yakisoba', DishVerdict.nonKeto),
          ('Rinderroulade mit Senf', DishVerdict.orderAsIs),
          ('Croquetas', DishVerdict.modifiable),
        ])
          (
            _dish(name),
            _analysed(
              _dish(name),
              verdict: verdict,
              modification: verdict == DishVerdict.modifiable
                  ? 'No bread'
                  : null,
            ),
          ),
      ];
      for (final profile in <DietaryProfile>[
        DietaryProfile.empty,
        _profile(<RestrictionId>[RestrictionId.keto]),
      ]) {
        for (final (dish, analysed) in dishes) {
          final without = ProfileEvaluator.evaluate(analysed, dish, profile);
          for (final trip in TripDestination.values) {
            expect(
              ProfileEvaluator.evaluate(analysed, dish, profile, trip: trip),
              without,
              reason: '${dish.name} in ${trip.name}',
            );
          }
        }
      }
    });

    test('the classification options ignore the trip', () {
      for (final trip in TripDestination.values) {
        for (final bantoMode in <bool>[false, true]) {
          final base = AppSettings(
            profile: _profile(<RestrictionId>[RestrictionId.sesame]),
          );
          expect(
            ClassificationOptions.fromSettings(
              base.copyWith(tripDestination: trip),
              bantoMode: bantoMode,
            ),
            ClassificationOptions.fromSettings(base, bantoMode: bantoMode),
          );
        }
      }
    });
  });

  group('the briefing', () {
    test('lists only the entries that hide something in the profile, in '
        "the lexicon's order", () {
      final entries = TripLexicon.briefing(
        TripDestination.japan,
        _profile(<RestrictionId>[RestrictionId.sesame]),
      );
      expect(entries.map((e) => e.terms.first), <String>['furikake', 'goma']);
    });

    test('keto alone lists nothing', () {
      for (final trip in TripDestination.values) {
        expect(
          TripLexicon.briefing(
            trip,
            _profile(<RestrictionId>[RestrictionId.keto]),
          ),
          isEmpty,
        );
      }
    });

    test('a vegetarian in Japan learns dashi is fish', () {
      expect(
        TripLexicon.briefing(
          TripDestination.japan,
          _profile(<RestrictionId>[RestrictionId.vegetarian]),
        ).map((e) => e.terms.first),
        contains('dashi'),
      );
    });
  });
}
