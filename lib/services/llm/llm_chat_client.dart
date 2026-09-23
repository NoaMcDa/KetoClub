import 'package:flutter/foundation.dart';

/// Why an [LlmChatClient] call produced a [ChatFailed] result instead of
/// a [ChatCompleted] one (architecture.md §9.3, §10).
///
/// Five of these — [notConfigured], [offline], [timeout], [rateLimited]
/// and [badResponse] — are also the `reason` vocabulary KetoClub's
/// backend answers with, so a client can map the wire value by name.
/// [backendUnreachable] never comes from the wire: it is what a client
/// reports when it could not reach the backend at all.
enum ChatFailureReason {
  /// No model is available: this build has no backend URL, or the
  /// backend has no model credentials configured (it answers 503).
  notConfigured,

  /// No network route was available between the backend and the model
  /// provider.
  offline,

  /// The request exceeded its time budget.
  timeout,

  /// The model provider's quota is exhausted; the backend answered 429.
  rateLimited,

  /// Another error status, or a response the client could not use.
  badResponse,

  /// KetoClub's backend could not be reached: a socket or DNS error
  /// before any HTTP status was received.
  backendUnreachable,
}

/// The outcome of one [LlmChatClient.complete] call (architecture.md §9,
/// §10).
///
/// Not constructed directly; use [ChatCompleted] or [ChatFailed].
@immutable
sealed class ChatResult {
  /// Subclasses only.
  const new();
}

/// A successful chat completion.
@immutable
final class ChatCompleted extends ChatResult {
  /// Creates a result carrying the raw reply [content] from [model].
  const new({required this.content, required this.model});

  /// The raw reply text, not yet parsed against a schema.
  final String content;

  /// The model id that produced [content].
  final String model;

  @override
  bool operator ==(Object other) =>
      other is ChatCompleted &&
      other.content == content &&
      other.model == model;

  @override
  int get hashCode => Object.hash(runtimeType, content, model);

  @override
  String toString() => 'ChatCompleted($model)';
}

/// A failed chat completion.
///
/// Never carries the upstream response body: it can echo request
/// content or headers (architecture.md §10, §11). A [statusCode] is the
/// only detail this type can carry beyond [reason].
@immutable
final class ChatFailed extends ChatResult {
  /// Creates a failure for [reason], with the HTTP [statusCode] received,
  /// when one was.
  const new({required this.reason, this.statusCode});

  /// Why the call failed.
  final ChatFailureReason reason;

  /// The HTTP status code received, or null when none was — for example
  /// [ChatFailureReason.offline] or [ChatFailureReason.timeout].
  ///
  /// Never the upstream response body.
  final int? statusCode;

  @override
  bool operator ==(Object other) =>
      other is ChatFailed &&
      other.reason == reason &&
      other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash(runtimeType, reason, statusCode);

  @override
  String toString() => 'ChatFailed($reason)';
}

/// A single chat completion call to a hosted language model
/// (architecture.md §9). Implementations never let a response body reach
/// a [ChatFailed] or a log.
abstract interface class LlmChatClient {
  /// Sends [systemPrompt] and [userPrompt] as one chat completion,
  /// requesting structured output shaped by [responseSchema] under
  /// [schemaName] when both are given.
  ///
  /// Always resolves to a [ChatResult], whether or not a schema was
  /// requested. Never throws.
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
  });
}
