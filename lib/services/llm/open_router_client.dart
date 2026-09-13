import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// [LlmChatClient] backed by OpenRouter's chat-completions gateway
/// (architecture.md §9.3, §10, §11).
///
/// **The model pin.** [defaultOpenRouterModel] and the latencies in this
/// comment come from `m15_openrouter_models_fix.md`, not from this
/// change: `openrouter.ai` is blocked from this build environment, so
/// the pre-release check architecture.md §9.3 asks for — running the
/// real system prompt against the pinned id and confirming it answers
/// in under [llmReleaseCheckSeconds] seconds — could not be run here and
/// is outstanding until the host is reachable from CI. The 8-12 s
/// figure for `nex-agi/nex-n2.5-pro:free` is a measurement from that
/// document, not one taken by this change. [documentedFallbackModels]
/// were measured in the same document at 32 s and 52 s respectively —
/// both well inside [llmRequestTimeout] but too slow to prefer over the
/// pin. Free-tier model ids retire without notice, which is what made
/// the M15 outage (a retired id, answering 404) look like "no internet"
/// to users before the failure reasons below were separated out; a 404
/// on the pinned model here is [ChatFailureReason.badResponse], never
/// [ChatFailureReason.offline].
///
/// **The fallback.** [rejectsRequestShape] governs the *only* retry
/// this class performs: a strict `json_schema` request answered 400,
/// 404 or 422 is re-sent exactly once, changed only to
/// `response_format: {"type": "json_object"}`
/// (`m16_structured_output_fix.md`). Nothing else is re-sent — see that
/// method's doc comment.
///
/// **The key.** Read from [KeyStore] on every call and sent only as the
/// `Authorization` header, never in the request body and never in a
/// [ChatFailed]. No key stored maps to
/// [ChatFailureReason.unauthorised]: this client cannot invent one.
final class OpenRouterClient implements LlmChatClient {
  /// Creates a client that sends requests through [client] and reads
  /// the user's API key from [keyStore] on every [complete] call.
  ///
  /// [model] is the gateway model id requested; [timeout] bounds each
  /// individual HTTP attempt (a schema-shape retry gets its own full
  /// [timeout], not a shared budget); [maxTokens] is sent as
  /// `max_tokens`.
  ///
  /// `client` and `keyStore` are named without their leading underscore
  /// so they cannot be initializing formals (`this._client` would make
  /// the parameter itself private and unusable at the call site) and
  /// are assigned explicitly instead.
  new({
    required http.Client client,
    required KeyStore keyStore,
    this.model = defaultOpenRouterModel,
    this.timeout = llmRequestTimeout,
    this.maxTokens = llmMaxOutputTokens,
  }) : // `client` is named without a leading underscore so it cannot be
       // an initializing formal (`this._client` would make the
       // parameter itself private and unusable at the call site).
       // ignore: prefer_initializing_formals
       _client = client,
       // Same reason as `_client` above, for `keyStore`.
       // ignore: prefer_initializing_formals
       _keyStore = keyStore;

  /// The pinned free-tier model (architecture.md §9.3). See the class
  /// doc comment for what is and is not known about its latency.
  static const String defaultOpenRouterModel = 'nex-agi/nex-n2.5-pro:free';

  /// Documented alternatives to [defaultOpenRouterModel], in preference
  /// order. Not a silent fallback list this class chooses from — a 404
  /// on the pinned model is surfaced as [ChatFailureReason.badResponse],
  /// and choosing a different model is a product decision that needs a
  /// settings screen (`m15_openrouter_models_fix.md`).
  static const List<String> documentedFallbackModels = <String>[
    'dots-studio/dots-3-note-preview:free',
    'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
  ];

  /// Whether [status] means the gateway refused the request's *shape*
  /// — a `json_schema` parameter it does not support, or a schema that
  /// failed strict-mode validation — rather than answering about the
  /// key, the quota, or the provider.
  ///
  /// Exactly `400`, `404`, or `422`. This is the only status class
  /// [complete] retries, and it retries it exactly once, changed only
  /// to a `json_object` response format
  /// (`m16_structured_output_fix.md` "How a strict `json_schema`
  /// request is refused"). 401, 403, 429 and 5xx are never retried:
  /// they are answers about the key, the quota, and the provider, and a
  /// different `response_format` changes none of them. A request that
  /// carried no schema to begin with is never re-sent either, since
  /// [complete] only checks this when a schema was requested.
  static bool rejectsRequestShape(int status) =>
      status == 400 || status == 404 || status == 422;

  /// The gateway endpoint every request is sent to. The only occurrence
  /// of `openrouter.ai` allowed under `lib/` (a boundary check enforces
  /// this).
  static final Uri _endpoint = Uri.parse(
    'https://openrouter.ai/api/v1/chat/completions',
  );

  /// `HTTP-Referer` sent with every request. OpenRouter asks apps to
  /// identify themselves this way, and doing so is also what lets a
  /// request work from a browser origin (architecture.md §9.3).
  ///
  /// The repository URL rather than a product domain, because KetoClub does
  /// not own one: claiming a hostname the project has not registered would be
  /// a false attribution in someone else's dashboard.
  static const String _referer = 'https://github.com/NoaMcDa/KetoClub';

  /// `X-Title` sent with every request, alongside [_referer]
  /// (architecture.md §9.3).
  static const String _title = 'KetoClub';

  /// The gateway model id requested with every call.
  final String model;

  /// How long a single HTTP attempt is given before it is abandoned. A
  /// slow model is not an offline device, so an attempt that exceeds
  /// this maps to [ChatFailureReason.timeout], never
  /// [ChatFailureReason.offline] (architecture.md §9.3).
  final Duration timeout;

  /// `max_tokens` sent with every request.
  final int maxTokens;

  final http.Client _client;
  final KeyStore _keyStore;

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
  }) async {
    final key = await _keyStore.read();
    if (key == null) {
      return const ChatFailed(reason: ChatFailureReason.unauthorised);
    }

    // response_format is only ever sent when both a schema and its name
    // were given; a call missing either has no shape to fall back from,
    // so the retry below never triggers for it.
    final hasSchema = responseSchema != null && schemaName != null;

    http.Response response;
    try {
      response = await _attempt(
        key: key,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        responseSchema: hasSchema ? responseSchema : null,
        schemaName: hasSchema ? schemaName : null,
      );
    } on TimeoutException {
      return const ChatFailed(reason: ChatFailureReason.timeout);
    } on http.ClientException {
      return const ChatFailed(reason: ChatFailureReason.offline);
    }

    if (hasSchema && rejectsRequestShape(response.statusCode)) {
      try {
        response = await _attempt(
          key: key,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          forceJsonObject: true,
        );
      } on TimeoutException {
        return const ChatFailed(reason: ChatFailureReason.timeout);
      } on http.ClientException {
        return const ChatFailed(reason: ChatFailureReason.offline);
      }
    }

    return _read(response);
  }

  Future<http.Response> _attempt({
    required String key,
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
    bool forceJsonObject = false,
  }) {
    final body = _body(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      responseSchema: responseSchema,
      schemaName: schemaName,
      forceJsonObject: forceJsonObject,
    );
    return _client
        .post(
          _endpoint,
          headers: <String, String>{
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            'HTTP-Referer': _referer,
            'X-Title': _title,
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
  }

  Map<String, Object?> _body({
    required String systemPrompt,
    required String userPrompt,
    required Map<String, Object?>? responseSchema,
    required String? schemaName,
    required bool forceJsonObject,
  }) {
    final body = <String, Object?>{
      'model': model,
      'messages': <Map<String, Object?>>[
        <String, Object?>{'role': 'system', 'content': systemPrompt},
        <String, Object?>{'role': 'user', 'content': userPrompt},
      ],
      'max_tokens': maxTokens,
    };
    if (forceJsonObject) {
      body['response_format'] = <String, Object?>{'type': 'json_object'};
    } else if (responseSchema != null && schemaName != null) {
      body['response_format'] = <String, Object?>{
        'type': 'json_schema',
        'json_schema': <String, Object?>{
          'name': schemaName,
          'strict': true,
          'schema': responseSchema,
        },
      };
    }
    return body;
  }

  ChatResult _read(http.Response response) {
    final statusCode = response.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      return ChatFailed(
        reason: ChatFailureReason.unauthorised,
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return ChatFailed(
        reason: ChatFailureReason.rateLimited,
        statusCode: statusCode,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      return ChatFailed(
        reason: ChatFailureReason.badResponse,
        statusCode: statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return ChatFailed(
        reason: ChatFailureReason.badResponse,
        statusCode: statusCode,
      );
    }

    final content = _extractContent(decoded);
    if (content == null) {
      return ChatFailed(
        reason: ChatFailureReason.badResponse,
        statusCode: statusCode,
      );
    }

    return ChatCompleted(content: content, model: model);
  }

  /// Pulls `choices[0].message.content` out of a decoded OpenRouter
  /// response body, or null when [decoded] is not shaped that way.
  String? _extractContent(Object? decoded) {
    if (decoded is! Map<String, Object?>) return null;
    final choices = decoded['choices'];
    if (choices is! List<Object?> || choices.isEmpty) return null;
    final first = choices[0];
    if (first is! Map<String, Object?>) return null;
    final message = first['message'];
    if (message is! Map<String, Object?>) return null;
    final content = message['content'];
    if (content is! String) return null;
    return content;
  }
}
