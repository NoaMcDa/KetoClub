/// Pre-release check for architecture.md §9.3 / §17.1 and issue #16:
/// measures real latency, structured-output support and
/// `MenuResponseParser` acceptance for the pinned OpenRouter model and its
/// documented fallbacks, using the *real* system/user prompt content
/// (architecture.md §9.1-§9.4) over a realistic 40-dish menu, in both
/// languages the app ships (architecture.md §12).
///
/// # Why this duplicates instead of importing
///
/// `MenuAnalysisPrompt`, `MenuResponseParser`, `OpenRouterClient` and the
/// `Menu`/`Dish`/`AnalysedDish` models all live under `lib/`, and every one
/// of them transitively imports `package:flutter/foundation.dart` (for
/// `@immutable` — architecture.md §18.2 allows only that one Flutter
/// import inside `models/`, `utils/` and `services/`). `foundation.dart` in
/// turn imports `dart:ui`, which does not exist outside a Flutter engine
/// process (`flutter test`, `flutter run`, `flutter drive`); it is not
/// available to the plain `dart` command this script is run with, even the
/// `dart` binary bundled inside the Flutter SDK. Confirmed empirically: any
/// attempt to `import 'package:ketoclub/services/classifier/
/// menu_analysis_prompt.dart';` from a script run with `dart run` fails
/// with "Error: Dart library 'dart:ui' is not available on this platform",
/// naming that exact import chain.
///
/// The pieces this script needs from `lib/` are therefore reproduced here
/// as plain, `dart:ui`-free Dart, kept behaviourally identical to their
/// `lib/` counterparts by `test/tool/measure_model_latency_test.dart` (run
/// under `flutter test`, which *does* have `dart:ui`): that file imports
/// both the real classes and this script's copies and asserts they agree
/// — on the exact prompt text, the exact schema, the exact pinned model id
/// and fallback list, and the exact eight parser rules (run against the
/// same `test/fixtures/llm_*.json` rule fixtures the real parser's own
/// tests use) — so a change to the real prompt, schema or parser that this
/// script does not follow fails the ordinary test suite rather than
/// silently going stale. The one piece imported directly,
/// [promptVerdictDefinitions] and [promptKetoRules] from
/// `lib/utils/constants.dart`, is pure Dart with no Flutter import at all,
/// so it is imported for real, never copied.
///
/// # Cost estimate formula (for the Settings screen, issue #16)
///
/// ```text
/// costUsd = promptTokens * pricing.prompt
///         + completionTokens * pricing.completion
/// ```
///
/// `promptTokens`/`completionTokens` come from the gateway response's own
/// `usage` object — never estimated from a character count, since
/// OpenRouter returns the real counts — and `pricing.prompt` /
/// `pricing.completion` are USD-per-token, read from `GET
/// https://openrouter.ai/api/v1/models` and matched by the request's
/// `model` id. This is a **per-menu** figure, not per-dish: architecture.md
/// D6 sends exactly one request per menu, however many dishes it holds, so
/// the number above is already the cost of analysing one visit's menu.
///
/// # Running it
///
/// ```sh
/// OPENROUTER_API_KEY=sk-... dart run tool/measure_model_latency.dart
/// ```
///
/// Run from the repository root (it reads the fixture menus with a path
/// relative to the working directory). See `tool/README.md` for what a
/// PASS/FAIL line means and what to do when the pinned model has retired.
// ignore_for_file: avoid_print — this is a CLI report; printing the
// findings is the entire job of this script.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ketoclub/utils/constants.dart';

/// Mirrors `OpenRouterClient.defaultOpenRouterModel`
/// (`lib/services/llm/open_router_client.dart`). Kept in sync by
/// `test/tool/measure_model_latency_test.dart` — see the module doc
/// comment for why it cannot be imported instead.
const String pinnedModel = 'nex-agi/nex-n2.5-pro:free';

/// Mirrors `OpenRouterClient.documentedFallbackModels`, same file, same
/// parity test.
const List<String> fallbackModels = <String>[
  'dots-studio/dots-3-note-preview:free',
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
];

/// Every model this script checks: the pin first, then its fallbacks, in
/// the order architecture.md §17.1 documents them.
List<String> get candidateModels => <String>[pinnedModel, ...fallbackModels];

/// Mirrors `MenuAnalysisPrompt._rolePreamble`
/// (`lib/services/classifier/menu_analysis_prompt.dart`) — private there,
/// so it cannot be imported; kept byte-identical by the parity test.
const String _rolePreamble =
    'You are the keto-diet menu analyst for KetoClub. Classify every dish '
    'in the user message into exactly one of three verdicts.';

/// Mirrors `MenuAnalysisPrompt._outputRules`, same file, same parity test.
const String _outputRules = '''
Every "modifiable" dish must carry a non-empty "modification" naming the exact component to remove and the exact substitute to ask for. A dish with no compliant path is "nonKeto" and must not carry a "modification".
Respond with JSON matching the supplied schema and nothing else: no markdown fence, no heading, no commentary before or after the JSON object.''';

/// Mirrors `MenuAnalysisPrompt.systemPrompt()` with no dietary
/// constraints — this script never sends any (architecture.md §9.1).
String buildSystemPrompt() {
  final buffer = StringBuffer()
    ..writeln(_rolePreamble)
    ..writeln()
    ..writeln(promptVerdictDefinitions)
    ..writeln()
    ..writeln(promptKetoRules)
    ..writeln()
    ..write(_outputRules);
  return buffer.toString();
}

/// One fixture dish, as read from a `test/fixtures/latency_menu_*.json`
/// file: `{id, category, name, description, options: [{name, values}]}`.
typedef FixtureDish = Map<String, Object?>;

/// Reads the dish list out of a `test/fixtures/latency_menu_*.json` file.
List<FixtureDish> loadFixtureMenu(String path) {
  final Object? decoded = jsonDecode(File(path).readAsStringSync());
  final root = decoded! as Map<String, Object?>;
  final rawDishes = root['dishes']! as List<Object?>;
  return rawDishes.cast<Map<String, Object?>>();
}

/// Mirrors `MenuAnalysisPrompt._optionText`.
String _optionText(Map<String, Object?> option) {
  final values = (option['values']! as List<Object?>).cast<String>();
  return '${option['name']}: ${values.join(', ')}';
}

/// Mirrors `MenuAnalysisPrompt._dishLine`.
String _dishLine(FixtureDish dish) {
  final options = (dish['options']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map(_optionText)
      .join('; ');
  return <String>[
    dish['id']! as String,
    dish['category']! as String,
    dish['name']! as String,
    dish['description']! as String,
    options,
  ].join(' | ');
}

/// Mirrors `MenuAnalysisPrompt.userPrompt(Menu)`, over a plain list of
/// [FixtureDish] instead of a `Menu` (see the module doc comment for why).
String buildUserPrompt(List<FixtureDish> dishes) =>
    dishes.map(_dishLine).join('\n');

/// The three `DishVerdict` names the schema's `verdict` enum and the
/// parser both recognise. `DishVerdict.values` itself cannot be read here
/// — the enum lives in `models/analysis.dart`, which is Flutter-tainted —
/// so these are literal; the parity test checks they still match
/// `DishVerdict.values.map((v) => v.name)`.
const List<String> verdictNames = <String>[
  'orderAsIs',
  'modifiable',
  'nonKeto',
];

/// Mirrors `MenuAnalysisPrompt.responseSchema()`.
Map<String, Object?> buildResponseSchema() => const <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['dishes'],
  'properties': <String, Object?>{
    'dishes': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>[
          'id',
          'name',
          'verdict',
          'why',
          'modification',
          'net_carbs_estimate',
        ],
        'properties': <String, Object?>{
          'id': <String, Object?>{'type': 'string'},
          'name': <String, Object?>{'type': 'string'},
          'verdict': <String, Object?>{'type': 'string', 'enum': verdictNames},
          'why': <String, Object?>{'type': 'string'},
          'modification': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'net_carbs_estimate': <String, Object?>{
            'type': <String>['number', 'null'],
          },
        },
      },
    },
  },
};

/// What [checkParserWouldAccept] found.
class ParserCheckResult {
  /// Creates a result.
  const new({
    required this.accepted,
    required this.detail,
    required this.placedCount,
  });

  /// True when the reply would come back from the real
  /// `MenuResponseParser.parse` as a `MenuAnalysed` (placed or not) rather
  /// than a `MenuAnalysisFailed`.
  ///
  /// Scoped to what this script's fixtures can actually exercise: with a
  /// non-empty 40-dish source menu, `MenuAnalysisFailureReason
  /// .noDishesFound` (rule 8) can only fire when the reply is empty *and*
  /// every source dish is somehow already accounted for, which cannot
  /// happen against these fixtures — the eight-rule fixture-by-fixture
  /// parity in `test/tool/measure_model_latency_test.dart` is what
  /// exercises rule 8 for real. So here `accepted` tracks only rules 1, 2
  /// and 6's `badResponse` cases: not JSON, a non-object root, a missing
  /// or non-list `dishes`, or more than [maxAnalysedDishes] entries.
  final bool accepted;

  /// Why [accepted] is false, or a one-line summary when it is true.
  final String detail;

  /// How many reply dishes matched a source dish, carried a recognised
  /// verdict and a non-empty `why`, and — if `modifiable` — a usable
  /// `modification` (rules 3-5). Diagnostic only; does not affect
  /// [accepted].
  final int placedCount;
}

/// A dependency-free reimplementation of `MenuResponseParser.parse`'s
/// `badResponse` checks (architecture.md §9.4 rules 1, 2 and 6) plus a
/// diagnostic per-dish placement count (rules 3-5), operating on
/// [FixtureDish] maps instead of `Menu`/`Dish` (see the module doc
/// comment for why). Kept behaviourally identical by
/// `test/tool/measure_model_latency_test.dart`, which runs both this
/// function and the real parser over the same `test/fixtures/llm_*.json`
/// rule fixtures and asserts they agree.
ParserCheckResult checkParserWouldAccept(
  String body, {
  required List<FixtureDish> sourceDishes,
}) {
  final trimmed = body.trim();
  final fenceMatch = RegExp(
    r'^```(?:json)?\s*\n?([\s\S]*?)\n?```$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  final unfenced = fenceMatch?.group(1)?.trim() ?? trimmed;

  final Object? decoded;
  try {
    decoded = jsonDecode(unfenced);
  } on FormatException {
    return const ParserCheckResult(
      accepted: false,
      detail: 'badResponse: reply is not JSON',
      placedCount: 0,
    );
  }
  if (decoded is! Map<String, Object?>) {
    return const ParserCheckResult(
      accepted: false,
      detail: 'badResponse: root is not a JSON object',
      placedCount: 0,
    );
  }
  final rawDishes = decoded['dishes'];
  if (rawDishes is! List<Object?>) {
    return const ParserCheckResult(
      accepted: false,
      detail: 'badResponse: "dishes" missing or not a list',
      placedCount: 0,
    );
  }
  if (rawDishes.length > maxAnalysedDishes) {
    return ParserCheckResult(
      accepted: false,
      detail:
          'badResponse: ${rawDishes.length} dishes exceeds '
          'maxAnalysedDishes ($maxAnalysedDishes)',
      placedCount: 0,
    );
  }

  final sourceIds = sourceDishes.map((dish) => dish['id']! as String).toSet();
  var placed = 0;
  for (final raw in rawDishes) {
    if (raw is! Map<String, Object?>) continue;
    final id = raw['id'] is String ? raw['id']! as String : '';
    if (!sourceIds.contains(id)) continue;

    final verdict = raw['verdict'];
    if (verdict is! String || !verdictNames.contains(verdict)) continue;

    final why = raw['why'];
    if (why is! String || why.trim().isEmpty) continue;

    if (verdict == 'modifiable') {
      final modification = raw['modification'];
      if (modification is! String ||
          modification.trim().isEmpty ||
          modification.trim().length > maxModificationLength) {
        continue;
      }
    }
    placed++;
  }

  return ParserCheckResult(
    accepted: true,
    detail: '$placed/${sourceDishes.length} dishes placed by id',
    placedCount: placed,
  );
}

/// One model's per-token USD pricing, read from `GET
/// https://openrouter.ai/api/v1/models`.
class ModelPricing {
  /// Creates a pricing record.
  const new({
    required this.promptUsdPerToken,
    required this.completionUsdPerToken,
  });

  /// USD per prompt (input) token.
  final double promptUsdPerToken;

  /// USD per completion (output) token.
  final double completionUsdPerToken;
}

/// Fetches per-token pricing for every model OpenRouter lists, keyed by
/// model id. Returns an empty map on any failure — a pricing miss is
/// reported as "unknown", never treated as free.
Future<Map<String, ModelPricing>> fetchModelPricing(http.Client client) async {
  final pricing = <String, ModelPricing>{};
  try {
    final response = await client
        .get(Uri.parse('https://openrouter.ai/api/v1/models'))
        .timeout(llmRequestTimeout);
    if (response.statusCode != 200) return pricing;
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    final data = decoded['data'];
    if (data is! List<Object?>) return pricing;
    for (final raw in data) {
      if (raw is! Map<String, Object?>) continue;
      final id = raw['id'];
      final rawPricing = raw['pricing'];
      if (id is! String || rawPricing is! Map<String, Object?>) continue;
      final prompt = double.tryParse('${rawPricing['prompt']}');
      final completion = double.tryParse('${rawPricing['completion']}');
      if (prompt == null || completion == null) continue;
      pricing[id] = ModelPricing(
        promptUsdPerToken: prompt,
        completionUsdPerToken: completion,
      );
    }
  } on http.ClientException {
    return pricing;
  } on FormatException {
    return pricing;
  } on TimeoutException {
    return pricing;
  }
  return pricing;
}

/// One gateway attempt's plain outcome, before this script interprets it:
/// either a completion body and the model that actually served it, or a
/// status code this script could not get past.
class _GatewayAttempt {
  const new completed(this.content, this.servedModel, this.usage)
    : statusCode = null;
  const new failed(this.statusCode)
    : content = null,
      servedModel = null,
      usage = null;

  final String? content;
  final String? servedModel;
  final Map<String, Object?>? usage;
  final int? statusCode;
}

/// Sends one chat-completion request to OpenRouter with [responseFormat],
/// mirroring the request shape `OpenRouterClient.complete` builds
/// (architecture.md §9.3): the same headers, the same `max_tokens`, the
/// same per-attempt timeout.
Future<_GatewayAttempt> _sendOnce(
  http.Client client, {
  required String apiKey,
  required String model,
  required String systemPrompt,
  required String userPrompt,
  required Map<String, Object?> responseFormat,
}) async {
  final http.Response response;
  try {
    response = await client
        .post(
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://github.com/NoaMcDa/KetoClub',
            'X-Title': 'KetoClub',
          },
          body: jsonEncode(<String, Object?>{
            'model': model,
            'max_tokens': llmMaxOutputTokens,
            'response_format': responseFormat,
            'messages': <Map<String, Object?>>[
              <String, Object?>{'role': 'system', 'content': systemPrompt},
              <String, Object?>{'role': 'user', 'content': userPrompt},
            ],
          }),
        )
        .timeout(llmRequestTimeout);
  } on http.ClientException {
    // -1: no real HTTP status exists yet (a network-level failure, e.g.
    // the host is unreachable) — never a shape-refusal `_rejectsRequestShape`
    // would retry.
    return const _GatewayAttempt.failed(-1);
  } on TimeoutException {
    // -2: same reasoning as -1, for a request that never got a response
    // inside llmRequestTimeout.
    return const _GatewayAttempt.failed(-2);
  }
  if (response.statusCode != 200) {
    return _GatewayAttempt.failed(response.statusCode);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    return _GatewayAttempt.failed(response.statusCode);
  }
  if (decoded is! Map<String, Object?>) {
    return _GatewayAttempt.failed(response.statusCode);
  }
  final choices = decoded['choices'];
  if (choices is! List<Object?> || choices.isEmpty) {
    return _GatewayAttempt.failed(response.statusCode);
  }
  final first = choices.first;
  if (first is! Map<String, Object?>) {
    return _GatewayAttempt.failed(response.statusCode);
  }
  final message = first['message'];
  if (message is! Map<String, Object?>) {
    return _GatewayAttempt.failed(response.statusCode);
  }
  final content = message['content'];
  if (content is! String) {
    return _GatewayAttempt.failed(response.statusCode);
  }
  final servedModel = decoded['model'];
  final usage = decoded['usage'];
  return _GatewayAttempt.completed(
    content,
    servedModel is String ? servedModel : model,
    usage is Map<String, Object?> ? usage : null,
  );
}

/// True for exactly the statuses `OpenRouterClient.rejectsRequestShape`
/// retries with the `json_object` fallback (architecture.md §9.3).
bool _rejectsRequestShape(int statusCode) =>
    statusCode == 400 || statusCode == 404 || statusCode == 422;

/// One candidate model's result for one fixture menu.
class ModelRunResult {
  /// Creates a result.
  const new({
    required this.model,
    required this.language,
    required this.latency,
    required this.validJson,
    required this.usedJsonObjectFallback,
    required this.structuredOutputsSupported,
    required this.parserAccepted,
    required this.parserDetail,
    required this.costUsd,
    required this.errorDetail,
  });

  /// The requested model id (not necessarily the one that served it).
  final String model;

  /// `'en'` or `'he'`.
  final String language;

  /// Wall-clock time for the whole exchange, including a fallback retry
  /// if one happened. Null when the request never completed at all.
  final Duration? latency;

  /// Whether the final reply body was valid JSON matching the schema
  /// shape (before the parser's own rules run).
  final bool validJson;

  /// True when the strict `json_schema` request was refused
  /// (architecture.md §9.3's `rejectsRequestShape`) and the
  /// `json_object` fallback had to be sent instead.
  final bool usedJsonObjectFallback;

  /// True when the gateway accepted the strict `json_schema` request on
  /// the first attempt — i.e. structured outputs are supported for this
  /// model without the fallback.
  final bool structuredOutputsSupported;

  /// [ParserCheckResult.accepted] for the final reply.
  final bool parserAccepted;

  /// [ParserCheckResult.detail], or the error that stopped this run.
  final String parserDetail;

  /// The estimated USD cost of this one request, or null when pricing
  /// could not be read for this model.
  final double? costUsd;

  /// Set when the request could not be completed at all (network error,
  /// every attempt refused, timeout).
  final String? errorDetail;

  /// architecture.md §9.3 / issue #16's accept rule: valid JSON matching
  /// the schema, structured outputs supported or the fallback worked, and
  /// under [llmReleaseCheckSeconds].
  bool get passes =>
      errorDetail == null &&
      validJson &&
      parserAccepted &&
      (structuredOutputsSupported || usedJsonObjectFallback) &&
      latency != null &&
      latency! < const Duration(seconds: llmReleaseCheckSeconds);
}

/// Runs [model] once against [systemPrompt]/[userPrompt], applying the
/// same one-retry-on-shape-refusal strategy as `OpenRouterClient.complete`
/// (architecture.md §9.3), then checks the result the same way this
/// script checks everything else — see [checkParserWouldAccept].
Future<ModelRunResult> measureModel({
  required http.Client client,
  required String apiKey,
  required String model,
  required String language,
  required String systemPrompt,
  required String userPrompt,
  required List<FixtureDish> sourceDishes,
  required Map<String, ModelPricing> pricing,
}) async {
  final schema = buildResponseSchema();
  final stopwatch = Stopwatch()..start();

  var attempt = await _sendOnce(
    client,
    apiKey: apiKey,
    model: model,
    systemPrompt: systemPrompt,
    userPrompt: userPrompt,
    responseFormat: <String, Object?>{
      'type': 'json_schema',
      'json_schema': <String, Object?>{
        'name': 'menu_analysis',
        'strict': true,
        'schema': schema,
      },
    },
  );
  final structuredOutputsSupported = attempt.content != null;
  var usedFallback = false;

  if (attempt.content == null &&
      attempt.statusCode != null &&
      _rejectsRequestShape(attempt.statusCode!)) {
    usedFallback = true;
    attempt = await _sendOnce(
      client,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      responseFormat: const <String, Object?>{'type': 'json_object'},
    );
  }
  stopwatch.stop();

  if (attempt.content == null) {
    return ModelRunResult(
      model: model,
      language: language,
      latency: stopwatch.elapsed,
      validJson: false,
      usedJsonObjectFallback: usedFallback,
      structuredOutputsSupported: structuredOutputsSupported,
      parserAccepted: false,
      parserDetail: 'no reply (status ${attempt.statusCode})',
      costUsd: null,
      errorDetail: 'gateway refused the request (status ${attempt.statusCode})',
    );
  }

  final content = attempt.content!;
  Object? decoded;
  var validJson = true;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    validJson = false;
  }
  if (decoded is! Map<String, Object?> || decoded['dishes'] is! List<Object?>) {
    validJson = false;
  }

  final parserCheck = checkParserWouldAccept(
    content,
    sourceDishes: sourceDishes,
  );

  final usage = attempt.usage;
  final servedPricing = pricing[attempt.servedModel] ?? pricing[model];
  final double? costUsd;
  if (usage != null && servedPricing != null) {
    final promptTokens = (usage['prompt_tokens'] as num?)?.toDouble() ?? 0.0;
    final completionTokens =
        (usage['completion_tokens'] as num?)?.toDouble() ?? 0.0;
    costUsd =
        promptTokens * servedPricing.promptUsdPerToken +
        completionTokens * servedPricing.completionUsdPerToken;
  } else {
    costUsd = null;
  }

  return ModelRunResult(
    model: model,
    language: language,
    latency: stopwatch.elapsed,
    validJson: validJson,
    usedJsonObjectFallback: usedFallback,
    structuredOutputsSupported: !usedFallback && structuredOutputsSupported,
    parserAccepted: parserCheck.accepted,
    parserDetail: parserCheck.detail,
    costUsd: costUsd,
    errorDetail: null,
  );
}

/// Reads `OPENROUTER_API_KEY`, runs [candidateModels] against both fixture
/// menus, prints a PASS/FAIL report, and exits non-zero when [pinnedModel]
/// fails either language (architecture.md §9.3's pre-release check).
Future<void> main() async {
  final apiKey = Platform.environment['OPENROUTER_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print(
      'measure_model_latency: OPENROUTER_API_KEY is not set. See '
      'tool/README.md for how to run this check.',
    );
    exitCode = 1;
    return;
  }

  final fixtures = <String, List<FixtureDish>>{
    'en': loadFixtureMenu('test/fixtures/latency_menu_en.json'),
    'he': loadFixtureMenu('test/fixtures/latency_menu_he.json'),
  };
  final systemPrompt = buildSystemPrompt();

  final client = http.Client();
  var pinnedFailed = false;
  try {
    print('measure_model_latency: fetching model pricing...');
    final pricing = await fetchModelPricing(client);

    for (final model in candidateModels) {
      for (final language in <String>['en', 'he']) {
        final dishes = fixtures[language]!;
        final userPrompt = buildUserPrompt(dishes);
        print('--- $model ($language) ---');
        final result = await measureModel(
          client: client,
          apiKey: apiKey,
          model: model,
          language: language,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          sourceDishes: dishes,
          pricing: pricing,
        );
        _printResult(result);
        if (model == pinnedModel && !result.passes) pinnedFailed = true;
      }
    }
  } finally {
    client.close();
  }

  if (pinnedFailed) {
    print(
      'measure_model_latency: FAIL — the pinned model '
      '($pinnedModel) did not pass for at least one language. See '
      'tool/README.md for what to do next.',
    );
    exitCode = 1;
  } else {
    print('measure_model_latency: pinned model passed for both languages.');
  }
}

/// Prints one [ModelRunResult] in the report's line format.
void _printResult(ModelRunResult result) {
  final verdict = result.passes ? 'PASS' : 'FAIL';
  final latencyText = result.latency == null
      ? 'n/a'
      : '${result.latency!.inMilliseconds}ms';
  final costText = result.costUsd == null
      ? 'unknown'
      : '\$${result.costUsd!.toStringAsFixed(6)}';
  print(
    '$verdict  latency=$latencyText  validJson=${result.validJson}  '
    'structuredOutputs=${result.structuredOutputsSupported}  '
    'jsonObjectFallback=${result.usedJsonObjectFallback}  '
    'parserAccepted=${result.parserAccepted} (${result.parserDetail})  '
    'costPerMenu=$costText'
    '${result.errorDetail == null ? '' : '  error=${result.errorDetail}'}',
  );
}
