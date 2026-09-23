/// The LLM-facing prompt and strict response schema for menu analysis
/// (architecture.md §9.1, §9.2).
///
/// Every model-facing rule this class states about the verdicts and the
/// keto vocabulary is read from `constants.dart`
/// ([promptVerdictDefinitions], [promptKetoRules]) rather than restated
/// here, so the system prompt and the UI legend cannot drift apart
/// (architecture.md §9.1).
library;

import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/utils/constants.dart';

/// Output rules architecture.md §9.1 states beyond the verdict
/// definitions and keto rules already in [promptKetoRules]: the
/// modification/schema/format requirements that are this prompt's own
/// contribution rather than shared vocabulary.
const String _outputRules = '''
Every "modifiable" dish must carry a non-empty "modification" naming the exact component to remove and the exact substitute to ask for. A dish with no compliant path is "nonKeto" and must not carry a "modification".
Respond with JSON matching the supplied schema and nothing else: no markdown fence, no heading, no commentary before or after the JSON object.''';

/// Introduces the model's role and the three-verdict task, before
/// [promptVerdictDefinitions] and [promptKetoRules] are appended verbatim
/// (architecture.md §9.1).
const String _rolePreamble =
    'You are the keto-diet menu analyst for KetoClub. Classify every dish '
    'in the user message into exactly one of three verdicts.';

/// Introduces [ClassificationOptions.dietaryConstraints] when the caller
/// supplied any (architecture.md §9.1, Tier C).
const String _dietaryConstraintsPreamble =
    'The user has these additional dietary constraints. A dish that '
    'violates one is not orderAsIs even if it otherwise would be — mark '
    'it modifiable or nonKeto, whichever fits:';

/// Builds the system prompt, user prompt, and strict JSON schema
/// `LlmMenuClassifier` sends to the model through `LlmChatClient`
/// (architecture.md §9.1, §9.2, §9.3).
///
/// Static and pure: no field, no constructor, nothing to fake.
abstract final class MenuAnalysisPrompt {
  /// The schema name sent in the strict `response_format`
  /// (architecture.md §9.3).
  static const String schemaName = 'menu_analysis';

  /// The system prompt: [promptVerdictDefinitions] and [promptKetoRules]
  /// verbatim from `constants.dart`, this prompt's own output rules, and
  /// — when [options] carries any — its
  /// [ClassificationOptions.dietaryConstraints] appended as a final
  /// section.
  ///
  /// The three verdicts and the keto rules are never restated or
  /// paraphrased here: they are read from `constants.dart` so the model
  /// and the UI legend describe the same three verdicts the same way
  /// (architecture.md §9.1).
  static String systemPrompt({
    ClassificationOptions options = const ClassificationOptions(),
  }) {
    final buffer = StringBuffer()
      ..writeln(_rolePreamble)
      ..writeln()
      ..writeln(promptVerdictDefinitions)
      ..writeln()
      ..writeln(promptKetoRules)
      ..writeln()
      ..write(_outputRules);
    final constraints = options.dietaryConstraints;
    if (constraints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln()
        ..writeln(_dietaryConstraintsPreamble);
      for (var i = 0; i < constraints.length; i++) {
        if (i > 0) buffer.writeln();
        buffer.write('- ${constraints[i]}');
      }
    }
    return buffer.toString();
  }

  /// The menu as one line per dish, in menu order:
  /// `id | category | name | description | options`.
  ///
  /// Prices are omitted: they play no part in a keto verdict and would
  /// only spend tokens the model reads and discards (architecture.md
  /// §9.1). Each of a dish's [DishOption] groups is flattened to its
  /// label and its value labels, joined with `; ` when a dish carries
  /// more than one group.
  static String userPrompt(Menu menu) {
    final lines = <String>[];
    for (final category in menu.categories) {
      for (final dish in category.dishes) {
        lines.add(_dishLine(dish, category.name));
      }
    }
    return lines.join('\n');
  }

  /// One `userPrompt` line for [dish], under [categoryName].
  static String _dishLine(Dish dish, String categoryName) {
    final options = dish.options.map(_optionText).join('; ');
    return <String>[
      dish.id,
      categoryName,
      dish.name,
      dish.description,
      options,
    ].join(' | ');
  }

  /// Flattens one [DishOption] to `label: value, value, ...`.
  static String _optionText(DishOption option) =>
      '${option.name}: ${option.values.join(', ')}';

  /// The strict JSON schema for the reply (architecture.md §9.2).
  ///
  /// Every one of the six dish properties is listed in `required`, and
  /// both the outer object and the dish object carry
  /// `additionalProperties: false` — OpenAI-style strict mode demands
  /// both, and `m16_structured_output_fix.md` documents the outage a
  /// different project's schema caused by missing them.
  /// `modification` and `net_carbs_estimate` are typed
  /// `["string"/"number", "null"]` rather than omitted, because strict
  /// mode has no way to say "optional": the model is required to send
  /// `null` where `MenuResponseParser` treats it as absent.
  ///
  /// Deliberately absent: a `description` property.
  /// `m16_structured_output_fix.md` describes a *different* project's
  /// analyser that echoed the dish description back on every reply; this
  /// parser never reads one back — `MenuResponseParser` has no use for
  /// it — so requiring it here would only force the model to spend
  /// output tokens re-typing text this app discards, against the output
  /// token budget the server sets for every request, which
  /// `m16_structured_output_fix.md`'s own "what was not verified"
  /// section names as the remaining suspect if a real request still
  /// fails. Do not add a `description` property back without also
  /// raising that budget on the server.
  static Map<String, Object?> responseSchema() => <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': const <String>['dishes'],
    'properties': <String, Object?>{
      'dishes': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'required': const <String>[
            'id',
            'name',
            'verdict',
            'why',
            'modification',
            'net_carbs_estimate',
          ],
          'properties': <String, Object?>{
            'id': const <String, Object?>{'type': 'string'},
            'name': const <String, Object?>{'type': 'string'},
            'verdict': <String, Object?>{
              'type': 'string',
              'enum': DishVerdict.values
                  .map((verdict) => verdict.name)
                  .toList(),
            },
            'why': const <String, Object?>{'type': 'string'},
            'modification': const <String, Object?>{
              'type': <String>['string', 'null'],
            },
            'net_carbs_estimate': const <String, Object?>{
              'type': <String>['number', 'null'],
            },
          },
        },
      },
    },
  };
}
