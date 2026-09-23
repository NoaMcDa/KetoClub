import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// The only [ChatFailureReason] values KetoClub's backend ever sends as
/// the `reason` of an error body (`backend_plan.md` §3.2).
///
/// [ChatFailureReason.backendUnreachable] is deliberately absent: it
/// describes the client failing to reach the server at all, so a body
/// claiming it is not a body this client trusts, and reads as
/// [ChatFailureReason.badResponse] instead.
const Set<ChatFailureReason> _wireReasons = <ChatFailureReason>{
  ChatFailureReason.notConfigured,
  ChatFailureReason.offline,
  ChatFailureReason.timeout,
  ChatFailureReason.rateLimited,
  ChatFailureReason.badResponse,
};

/// [LlmChatClient] backed by KetoClub's own backend (`backend_plan.md`
/// §3.2), which holds the model credentials and forwards the request to
/// the model provider.
///
/// **No credentials on the device.** This client sends no
/// `Authorization` header — the backend answers 400 to one — and no API
/// key of any kind. The only identifying value it sends is the anonymous
/// install id, as `X-KetoClub-Install-Id`, which the backend uses for
/// rate-limiting alone (architecture.md D8).
///
/// **No retries.** One [complete] call is exactly one request. Nothing
/// pre-checks whether the server is up: the call is the probe
/// (architecture.md §14 D10), and a socket or DNS failure is
/// [ChatFailureReason.backendUnreachable], never
/// [ChatFailureReason.offline] — the server's own `offline` means *it*
/// could not reach the model provider.
///
/// **The body never escapes.** An error body's `reason` is read and
/// mapped by name; nothing else from it reaches a [ChatFailed].
final class BackendChatClient implements LlmChatClient {
  /// Creates a client that posts to [baseUrl]'s `/v1/chat` through
  /// [client], identifying the install with [installIdStore]'s id.
  ///
  /// A null [baseUrl] means this build has no backend configured: every
  /// [complete] call then resolves to [ChatFailureReason.notConfigured]
  /// without any I/O at all — not even reading the install id.
  ///
  /// [timeout] bounds the single HTTP request; exceeding it is
  /// [ChatFailureReason.timeout].
  ///
  /// `client` and `installIdStore` are named without their leading
  /// underscore so they cannot be initializing formals (`this._client`
  /// would make the parameter itself private and unusable at the call
  /// site) and are assigned explicitly instead.
  new({
    required http.Client client,
    required this.baseUrl,
    required InstallIdStore installIdStore,
    this.timeout = llmRequestTimeout,
  }) : // See the constructor doc for why this is not an initializing
       // formal.
       // ignore: prefer_initializing_formals
       _client = client,
       // Same reason as `_client` above, for `installIdStore`.
       // ignore: prefer_initializing_formals
       _installIdStore = installIdStore;

  /// The header carrying the anonymous install id (`backend_plan.md`
  /// §3.4).
  static const String installIdHeader = 'X-KetoClub-Install-Id';

  /// KetoClub's backend, or null when this build has none.
  final Uri? baseUrl;

  /// How long the single HTTP request is given before it is abandoned.
  final Duration timeout;

  final http.Client _client;
  final InstallIdStore _installIdStore;

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
  }) async {
    final baseUrl = this.baseUrl;
    if (baseUrl == null) {
      return const ChatFailed(reason: ChatFailureReason.notConfigured);
    }

    final installId = await _installIdStore.id();
    final body = <String, Object?>{
      'system_prompt': systemPrompt,
      'user_prompt': userPrompt,
      'response_schema': ?responseSchema,
      'schema_name': ?schemaName,
    };

    final http.Response response;
    try {
      response = await _client
          .post(
            _chatUri(baseUrl),
            headers: <String, String>{
              'Content-Type': 'application/json',
              installIdHeader: installId,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      return const ChatFailed(reason: ChatFailureReason.timeout);
    } on http.ClientException {
      return const ChatFailed(reason: ChatFailureReason.backendUnreachable);
    }

    return _read(response);
  }

  /// The chat endpoint under [base]: `{base}/v1/chat`, whether or not
  /// [base] itself ends with a trailing slash.
  static Uri _chatUri(Uri base) {
    final rendered = base.toString();
    final trimmed = rendered.endsWith('/')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
    return Uri.parse('$trimmed/v1/chat');
  }

  ChatResult _read(http.Response response) {
    final statusCode = response.statusCode;
    final decoded = _decode(response);

    if (statusCode >= 200 && statusCode < 300) {
      if (decoded is Map<String, Object?>) {
        final content = decoded['content'];
        final model = decoded['model'];
        if (content is String && model is String) {
          return ChatCompleted(content: content, model: model);
        }
      }
      return ChatFailed(
        reason: ChatFailureReason.badResponse,
        statusCode: statusCode,
      );
    }

    return ChatFailed(reason: _reasonFrom(decoded), statusCode: statusCode);
  }

  /// The wire reason named by an error body's `reason` field, or
  /// [ChatFailureReason.badResponse] when [decoded] names none this
  /// client trusts: a non-JSON body, FastAPI's `{"detail": …}` 422, an
  /// unknown name, or a client-only one.
  static ChatFailureReason _reasonFrom(Object? decoded) {
    if (decoded is! Map<String, Object?>) return ChatFailureReason.badResponse;
    final name = decoded['reason'];
    if (name is! String) return ChatFailureReason.badResponse;
    for (final reason in _wireReasons) {
      if (reason.name == name) return reason;
    }
    return ChatFailureReason.badResponse;
  }

  /// [response]'s body decoded as JSON, or null when it is not JSON at
  /// all — including a body whose bytes are not valid in its declared
  /// encoding, which [http.Response.body] reports as a [FormatException]
  /// too.
  static Object? _decode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    }
  }
}
