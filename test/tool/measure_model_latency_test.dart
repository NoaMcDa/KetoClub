/// Parity tests for `tool/measure_model_latency.dart` (issue #16).
///
/// That script cannot import `MenuAnalysisPrompt`, `MenuResponseParser` or
/// `OpenRouterClient` directly — see its own doc comment for why
/// (`dart:ui` is unavailable to the plain `dart run` it is invoked with) —
/// so it keeps small, dependency-free copies of what it needs from them
/// instead. This file is what keeps those copies honest: it imports both
/// the real classes (this file runs under `flutter test`, which does have
/// `dart:ui`) and the script's copies, and asserts they agree. A change to
/// the real prompt, schema, pinned model or parser rules that the script
/// does not follow fails here, in the ordinary test suite, rather than
/// silently going stale until someone runs the script by hand.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/llm/open_router_client.dart';

import '../../tool/measure_model_latency.dart' as latency;

/// The venue every [Menu] built by this file is addressed to.
const VenueRef _venueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'measure-model-latency-parity-venue',
);

/// Builds a real [Menu] from a list of [latency.FixtureDish]s — the exact
/// shape `test/fixtures/latency_menu_*.json` holds and
/// `tool/measure_model_latency.dart` reads — so both sides of every
/// parity check below start from identical input.
Menu _menuFrom(List<latency.FixtureDish> dishes) {
  final byCategory = <String, List<Dish>>{};
  for (final dish in dishes) {
    final options = (dish['options']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(
          (option) => DishOption(
            name: option['name']! as String,
            values: (option['values']! as List<Object?>).cast<String>(),
          ),
        )
        .toList();
    byCategory
        .putIfAbsent(dish['category']! as String, () => <Dish>[])
        .add(
          Dish(
            id: dish['id']! as String,
            name: dish['name']! as String,
            description: dish['description']! as String,
            price: 0,
            options: options,
          ),
        );
  }
  return Menu(
    venueRef: _venueRef,
    currency: 'ILS',
    fetchedAt: DateTime.utc(2026),
    categories: [
      for (final entry in byCategory.entries)
        MenuCategory(
          id: 'cat-${entry.key}',
          name: entry.key,
          dishes: entry.value,
        ),
    ],
  );
}

/// Every `test/fixtures/llm_*.json` rule fixture the real
/// `MenuResponseParser`'s own tests use (architecture.md §9.4), reused
/// here to check `checkParserWouldAccept` agrees with the real parser on
/// whether each one is accepted at all.
const List<String> _llmRuleFixtures = <String>[
  'llm_dishes_is_string.json',
  'llm_empty_dishes.json',
  'llm_empty_why.json',
  'llm_fenced_valid.json',
  'llm_green_with_modification.json',
  'llm_invalid_verdict.json',
  'llm_invented_dish.json',
  'llm_net_carbs_variants.json',
  'llm_not_json.json',
  'llm_prompt_injection.json',
  'llm_provenance_by_name_overlap.json',
  'llm_red_with_modification.json',
  'llm_root_is_list.json',
  'llm_skipped_dish.json',
  'llm_unknown_keys.json',
  'llm_why_overlength.json',
  'llm_yellow_blank_modification.json',
  'llm_yellow_null_modification.json',
  'llm_yellow_overlength_modification.json',
];

void main() {
  group('measure_model_latency parity with OpenRouterClient (#16)', () {
    test('pinnedModel matches OpenRouterClient.defaultOpenRouterModel', () {
      // Assert
      expect(latency.pinnedModel, OpenRouterClient.defaultOpenRouterModel);
    });

    test(
      'fallbackModels matches OpenRouterClient.documentedFallbackModels',
      () {
        // Assert
        expect(
          latency.fallbackModels,
          OpenRouterClient.documentedFallbackModels,
        );
      },
    );
  });

  group('measure_model_latency parity with MenuAnalysisPrompt (#16)', () {
    test('buildSystemPrompt matches MenuAnalysisPrompt.systemPrompt with no '
        'dietary constraints', () {
      // Act, Assert
      expect(latency.buildSystemPrompt(), MenuAnalysisPrompt.systemPrompt());
    });

    test('verdictNames matches DishVerdict.values, in order', () {
      // Act, Assert
      expect(
        latency.verdictNames,
        DishVerdict.values.map((verdict) => verdict.name).toList(),
      );
    });

    test('buildResponseSchema matches MenuAnalysisPrompt.responseSchema', () {
      // Act, Assert
      expect(
        latency.buildResponseSchema(),
        MenuAnalysisPrompt.responseSchema(),
      );
    });

    test('buildUserPrompt matches MenuAnalysisPrompt.userPrompt for the '
        'English fixture menu', () {
      // Arrange
      final dishes = latency.loadFixtureMenu(
        'test/fixtures/latency_menu_en.json',
      );
      final menu = _menuFrom(dishes);

      // Act, Assert
      expect(
        latency.buildUserPrompt(dishes),
        MenuAnalysisPrompt.userPrompt(menu),
      );
    });

    test('buildUserPrompt matches MenuAnalysisPrompt.userPrompt for the '
        'Hebrew fixture menu', () {
      // Arrange
      final dishes = latency.loadFixtureMenu(
        'test/fixtures/latency_menu_he.json',
      );
      final menu = _menuFrom(dishes);

      // Act, Assert
      expect(
        latency.buildUserPrompt(dishes),
        MenuAnalysisPrompt.userPrompt(menu),
      );
    });
  });

  group('measure_model_latency parity with MenuResponseParser (#16, '
      'architecture.md §9.4)', () {
    // A fixed, non-empty 40-dish source menu, shared by every case
    // below. With a non-empty source, MenuResponseParser.parse can
    // never return MenuAnalysisFailed(noDishesFound) (rule 8): rule 7
    // always fills `unclassified` with every source dish the reply did
    // not place, so `unclassified` is non-empty whenever `source` is —
    // which is exactly why checkParserWouldAccept's own doc comment
    // scopes `accepted` to rules 1, 2 and 6 only. This loop is what
    // proves that scoping is safe: for every one of the real parser's
    // rule fixtures, "the real parser returned MenuAnalysed" and "the
    // script says accepted" must still agree.
    final dishes = latency.loadFixtureMenu(
      'test/fixtures/latency_menu_en.json',
    );
    final menu = _menuFrom(dishes);

    for (final fixtureName in _llmRuleFixtures) {
      test('checkParserWouldAccept agrees with MenuResponseParser.parse on '
          '$fixtureName', () {
        // Arrange
        final body = File('test/fixtures/$fixtureName').readAsStringSync();

        // Act
        final realResult = MenuResponseParser.parse(
          body,
          source: menu,
          analysedAt: DateTime.utc(2026),
          engine: const RulesEngine(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
        );
        final scriptResult = latency.checkParserWouldAccept(
          body,
          sourceDishes: dishes,
        );

        // Assert
        expect(
          scriptResult.accepted,
          realResult is MenuAnalysed,
          reason:
              'real parser returned ${realResult.runtimeType} for '
              '$fixtureName but checkParserWouldAccept.accepted was '
              '${scriptResult.accepted}',
        );
      });
    }
  });

  group('measure_model_latency fixture menus (#16)', () {
    test('the English fixture menu has 40 dishes', () {
      // Act
      final dishes = latency.loadFixtureMenu(
        'test/fixtures/latency_menu_en.json',
      );

      // Assert
      expect(dishes, hasLength(40));
    });

    test('the Hebrew fixture menu has 40 dishes', () {
      // Act
      final dishes = latency.loadFixtureMenu(
        'test/fixtures/latency_menu_he.json',
      );

      // Assert
      expect(dishes, hasLength(40));
    });

    test('the Hebrew fixture menu is actually written in Hebrew', () {
      // Act
      final dishes = latency.loadFixtureMenu(
        'test/fixtures/latency_menu_he.json',
      );

      // Assert
      for (final dish in dishes) {
        expect(
          RegExp('[֐-׿]').hasMatch(dish['name']! as String),
          isTrue,
          reason: '${dish['name']} does not look like Hebrew',
        );
      }
    });
  });
}
