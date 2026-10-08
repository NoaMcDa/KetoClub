import 'package:flutter/foundation.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

/// An [LlmChatClient] that sends through [_primary] first and, only when
/// it could not answer at all, through [_fallback] (architecture.md D25;
/// issue #331).
///
/// The primary is meant to be KetoClub's backend (`BackendChatClient`) and
/// the fallback the phone's own key (`GeminiChatClient`), so that a phone
/// built with a backend still answers while the server is down. The chain
/// is `FallbackMenuClassifier`'s, with chat results in place of analyses:
///
/// 1. The primary's [ChatCompleted] is returned as it is.
/// 2. A primary failure [shouldFallBack] rejects is returned as it is,
///    and the fallback is never called: the server answered, and its
///    answer is about the request.
/// 3. Otherwise the fallback answers. Its [ChatCompleted] is returned; if
///    it fails too, the primary's failure is reported, unless the primary
///    only said [ChatFailureReason.notConfigured] — then the fallback's
///    is, since it is the one that tried.
///
/// Both clients get the same request. Consent is not checked here: every
/// caller already sits behind it. Never throws, as neither client does.
@immutable
final class FallbackChatClient implements LlmChatClient {
  /// Creates a chain sending through `primary`, then `fallback`.
  const new({required this._primary, required this._fallback});

  /// Whether a primary failure for [reason] is handed to the fallback:
  /// [ChatFailureReason.notConfigured],
  /// [ChatFailureReason.backendUnreachable], [ChatFailureReason.timeout]
  /// and [ChatFailureReason.rateLimited] — the backend could not answer
  /// this call — and nothing else.
  ///
  /// An exhaustive switch with no `default`, so a new reason has to be
  /// placed on one side or the other deliberately.
  static bool shouldFallBack(ChatFailureReason reason) {
    switch (reason) {
      case ChatFailureReason.notConfigured:
      case ChatFailureReason.backendUnreachable:
      case ChatFailureReason.timeout:
      case ChatFailureReason.rateLimited:
        return true;
      case ChatFailureReason.offline:
      case ChatFailureReason.badResponse:
      case ChatFailureReason.apiKeyMissing:
      case ChatFailureReason.apiKeyRejected:
        return false;
    }
  }

  final LlmChatClient _primary;
  final LlmChatClient _fallback;

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
    List<ChatImagePart> images = const <ChatImagePart>[],
  }) async {
    final first = await _primary.complete(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      responseSchema: responseSchema,
      schemaName: schemaName,
      images: images,
    );
    if (first is! ChatFailed || !shouldFallBack(first.reason)) return first;
    final second = await _fallback.complete(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      responseSchema: responseSchema,
      schemaName: schemaName,
      images: images,
    );
    return switch (second) {
      final ChatCompleted completed => completed,
      final ChatFailed failed =>
        first.reason == ChatFailureReason.notConfigured ? failed : first,
    };
  }
}
