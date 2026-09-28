import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/storage/api_key_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// Google's Generative Language API. The only place under `lib/` that
/// names Google's host (`test/architecture/import_rules_test.dart`).
const String _geminiHost = 'generativelanguage.googleapis.com';

/// The marker Gemini puts in a 400's `error.status`, `error.message` or
/// `error.details[].reason` when the key itself is invalid, as opposed to
/// the request.
const String _invalidKeyMarker = 'API_KEY_INVALID';

/// A key made only of visible ASCII — the only characters an HTTP header
/// value can carry safely, and the only ones a Google API key contains.
final RegExp _headerSafeKey = RegExp(r'^[\x21-\x7E]+$');

/// Converts a strict JSON schema to the OpenAPI subset Gemini accepts as
/// `responseSchema` — the same conversion the backend's
/// `to_gemini_schema` does (`backend/app/services/gemini.py`):
///
/// - `additionalProperties` is dropped: Gemini's schema has no such field.
/// - `"type": [T, "null"]` (either order) becomes `"type": T` plus
///   `"nullable": true`: Gemini takes one type name, not a union.
/// - `properties` values and `items` are converted recursively.
/// - Everything else (`enum`, `required`, `description`, …) is kept.
///
/// Pure: [schema] is never mutated and the result shares no mutable value
/// with it. Public so its test can pin each rule without HTTP.
Map<String, Object?> toGeminiSchema(Map<String, Object?> schema) {
  final converted = <String, Object?>{};
  for (final MapEntry(:key, :value) in schema.entries) {
    if (key == 'additionalProperties') continue;
    if (key == 'type' && value is List<Object?>) {
      final nonNull = value.where((type) => type != 'null').toList();
      if (nonNull.length == 1) {
        converted['type'] = nonNull.single;
        if (nonNull.length < value.length) converted['nullable'] = true;
        continue;
      }
    }
    if (key == 'properties' && value is Map<String, Object?>) {
      converted[key] = <String, Object?>{
        for (final MapEntry(key: name, value: sub) in value.entries)
          name: sub is Map<String, Object?> ? toGeminiSchema(sub) : _copy(sub),
      };
      continue;
    }
    if (key == 'items' && value is Map<String, Object?>) {
      converted[key] = toGeminiSchema(value);
      continue;
    }
    converted[key] = _copy(value);
  }
  return converted;
}

/// A deep copy of a decoded-JSON [value], so [toGeminiSchema]'s result
/// shares no list or map with its input.
Object? _copy(Object? value) => switch (value) {
  final Map<String, Object?> map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries) key: _copy(value),
  },
  final List<Object?> list => <Object?>[for (final item in list) _copy(item)],
  _ => value,
};

/// [LlmChatClient] that calls Google's Gemini API straight from the
/// device, with the user's own key — the iOS and Android path
/// (architecture.md D14). The web build uses `BackendChatClient` instead,
/// because a browser cannot hold the key safely and D12's backend already
/// holds one.
///
/// **The key goes to Google alone.** It is read from [ApiKeyStore] per
/// call, sent only as the `x-goog-api-key` header — never as `?key=` in
/// the URL, where it could surface in a log — and never reaches a
/// [ChatFailed], a log line or [toString].
///
/// **One retry, and only one kind.** Mirroring the backend's client: a
/// request carrying a schema that Gemini answers 400, for any reason
/// other than an invalid key, is re-sent exactly once with
/// `responseMimeType` only. 401, 403, 429 and 5xx are answers about the
/// key, the quota or the provider and are never re-sent; neither is a
/// second 400. Nothing pre-checks whether Google is reachable: the call is
/// the probe (architecture.md §14 D10).
///
/// **Failure mapping.** No saved key is [ChatFailureReason.apiKeyMissing]
/// with no I/O beyond the key read. A saved key holding a space, a control
/// character or anything outside ASCII — a paste that picked up more than
/// the key — is [ChatFailureReason.apiKeyRejected] without a request, since
/// no such value can travel in a header and no Google key contains one.
/// 401, 403 or a 400 naming an invalid key is
/// [ChatFailureReason.apiKeyRejected] too; 429 is
/// [ChatFailureReason.rateLimited] (the user's own key's quota); any other
/// status, or a reply with no usable text, is
/// [ChatFailureReason.badResponse]. A socket or DNS error is
/// [ChatFailureReason.offline] — there is no KetoClub server in between to
/// be unreachable — and exceeding [timeout] is
/// [ChatFailureReason.timeout].
final class GeminiChatClient implements LlmChatClient {
  /// Creates a client that posts to Gemini's `generateContent` for
  /// [model] through [client], with the key [apiKeyStore] holds.
  ///
  /// [timeout] bounds each HTTP request, the one retry included.
  ///
  /// `client` and `apiKeyStore` are named without their leading
  /// underscore so they cannot be initializing formals, and are assigned
  /// explicitly instead — the same choice `BackendChatClient` documents.
  new({
    required http.Client client,
    required ApiKeyStore apiKeyStore,
    this.model = defaultModel,
    this.timeout = llmRequestTimeout,
  }) : // See the constructor doc for why this is not an initializing
       // formal.
       // ignore: prefer_initializing_formals
       _client = client,
       // Same reason as `_client` above, for `apiKeyStore`.
       // ignore: prefer_initializing_formals
       _apiKeyStore = apiKeyStore;

  /// The model the phone calls unless told otherwise: the backend's own
  /// default (`GEMINI_MODEL`, D12), so web and phones classify alike.
  static const String defaultModel = 'gemini-2.5-flash';

  /// The header Gemini reads the API key from.
  static const String apiKeyHeader = 'x-goog-api-key';

  /// The reply budget, matching the backend's `GEMINI_MAX_OUTPUT_TOKENS`.
  static const int maxOutputTokens = 8192;

  /// The reasoning budget, matching the backend's
  /// `GEMINI_THINKING_BUDGET`: zero, so the whole output budget is spent
  /// on the JSON answer.
  static const int thinkingBudget = 0;

  /// The Gemini model id every request names.
  final String model;

  /// How long each HTTP request is given before it is abandoned.
  final Duration timeout;

  final http.Client _client;
  final ApiKeyStore _apiKeyStore;

  /// The `generateContent` endpoint for [model].
  Uri get endpoint =>
      Uri.https(_geminiHost, '/v1beta/models/$model:generateContent');

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
  }) async {
    // [schemaName] is accepted for the interface's sake: Gemini's
    // `responseSchema` has no name field, so there is nowhere to send it.
    final key = (await _apiKeyStore.read())?.trim();
    if (key == null || key.isEmpty) {
      return const ChatFailed(reason: ChatFailureReason.apiKeyMissing);
    }
    if (!_headerSafeKey.hasMatch(key)) {
      return const ChatFailed(reason: ChatFailureReason.apiKeyRejected);
    }

    final schema = responseSchema == null
        ? null
        : toGeminiSchema(responseSchema);

    var outcome = await _post(key, _body(systemPrompt, userPrompt, schema));
    if (outcome case _Answered(:final response)
        when schema != null &&
            response.statusCode == 400 &&
            !_isInvalidKey(response)) {
      outcome = await _post(key, _body(systemPrompt, userPrompt, null));
    }

    return switch (outcome) {
      _Answered(:final response) => _read(response),
      _TransportFailed(:final result) => result,
    };
  }

  Map<String, Object?> _body(
    String systemPrompt,
    String userPrompt,
    Map<String, Object?>? schema,
  ) => <String, Object?>{
    'system_instruction': <String, Object?>{
      'parts': <Object?>[
        <String, Object?>{'text': systemPrompt},
      ],
    },
    'contents': <Object?>[
      <String, Object?>{
        'role': 'user',
        'parts': <Object?>[
          <String, Object?>{'text': userPrompt},
        ],
      },
    ],
    'generationConfig': <String, Object?>{
      'responseMimeType': 'application/json',
      'maxOutputTokens': maxOutputTokens,
      'temperature': 0,
      'thinkingConfig': <String, Object?>{'thinkingBudget': thinkingBudget},
      'responseSchema': ?schema,
    },
  };

  Future<_Outcome> _post(String key, Map<String, Object?> body) async {
    try {
      final response = await _client
          .post(
            endpoint,
            headers: <String, String>{
              'Content-Type': 'application/json',
              apiKeyHeader: key,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return _Answered(response);
    } on TimeoutException {
      return const _TransportFailed(
        ChatFailed(reason: ChatFailureReason.timeout),
      );
    } on http.ClientException {
      return const _TransportFailed(
        ChatFailed(reason: ChatFailureReason.offline),
      );
    }
  }

  ChatResult _read(http.Response response) {
    final status = response.statusCode;
    if (status == 401 ||
        status == 403 ||
        (status == 400 && _isInvalidKey(response))) {
      return ChatFailed(
        reason: ChatFailureReason.apiKeyRejected,
        statusCode: status,
      );
    }
    if (status == 429) {
      return ChatFailed(
        reason: ChatFailureReason.rateLimited,
        statusCode: status,
      );
    }
    final decoded = status == 200 ? _decode(response) : null;
    final content = decoded is Map<String, Object?>
        ? _candidateText(decoded['candidates'])
        : null;
    if (decoded is! Map<String, Object?> || content == null) {
      return ChatFailed(
        reason: ChatFailureReason.badResponse,
        statusCode: status,
      );
    }
    final modelVersion = decoded['modelVersion'];
    return ChatCompleted(
      content: content,
      model: modelVersion is String && modelVersion.isNotEmpty
          ? modelVersion
          : model,
    );
  }

  /// Whether a 400 is Gemini's "API key not valid" rather than a bad
  /// request.
  static bool _isInvalidKey(http.Response response) {
    final decoded = _decode(response);
    if (decoded is! Map<String, Object?>) return false;
    final error = decoded['error'];
    if (error is! Map<String, Object?>) return false;

    final status = error['status'];
    if (status is String && status.contains(_invalidKeyMarker)) return true;
    final message = error['message'];
    if (message is String &&
        (message.contains(_invalidKeyMarker) ||
            message.toLowerCase().contains('api key not valid'))) {
      return true;
    }
    final details = error['details'];
    if (details is List<Object?>) {
      for (final detail in details) {
        if (detail is Map<String, Object?> &&
            detail['reason'] == _invalidKeyMarker) {
          return true;
        }
      }
    }
    return false;
  }

  /// The first candidate's joined text, or null when it is unusable.
  ///
  /// Unusable: no candidate, a `finishReason` other than `STOP` (a
  /// `MAX_TOKENS` reply is truncated JSON; a `SAFETY` one is empty), or no
  /// non-empty text part. Parts flagged `thought` are the model's
  /// reasoning, not its answer, and are skipped.
  static String? _candidateText(Object? candidates) {
    if (candidates is! List<Object?> || candidates.isEmpty) return null;
    final first = candidates.first;
    if (first is! Map<String, Object?> || first['finishReason'] != 'STOP') {
      return null;
    }
    final content = first['content'];
    if (content is! Map<String, Object?>) return null;
    final parts = content['parts'];
    if (parts is! List<Object?>) return null;
    final joined = parts
        .whereType<Map<String, Object?>>()
        .where((part) => part['text'] is String && part['thought'] != true)
        .map((part) => part['text']! as String)
        .join();
    return joined.isEmpty ? null : joined;
  }

  /// [response]'s body decoded as JSON, or null when it is not JSON at
  /// all — including bytes that are not valid UTF-8.
  ///
  /// Decoded from the raw bytes as UTF-8 rather than through
  /// [http.Response.body], which falls back to Latin-1 when a response
  /// names no charset: JSON is UTF-8 by definition (RFC 8259), and a
  /// Hebrew menu's reply must not turn to mojibake on its way to the
  /// parser.
  static Object? _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'GeminiChatClient($model)';
}

/// What one HTTP attempt produced: a response to read, or a transport
/// failure that already is the call's answer.
sealed class _Outcome {
  const new();
}

/// Gemini answered with some HTTP status.
final class _Answered extends _Outcome {
  const new(this.response);

  final http.Response response;
}

/// No status was received: a timeout or a socket/DNS error.
final class _TransportFailed extends _Outcome {
  const new(this.result);

  final ChatFailed result;
}
