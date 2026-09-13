import 'package:ketoclub/services/llm/llm_chat_client.dart';

/// One recorded call to [FakeLlmChatClient.complete], so a test can
/// assert what a prompt-building caller sent.
final class RecordedChatRequest {
  /// Creates a record of one `complete` call's arguments.
  const new({
    required this.systemPrompt,
    required this.userPrompt,
    required this.responseSchema,
    required this.schemaName,
  });

  /// The system prompt the call was made with.
  final String systemPrompt;

  /// The user prompt the call was made with.
  final String userPrompt;

  /// The response schema the call was made with, or null when none was
  /// requested.
  final Map<String, Object?>? responseSchema;

  /// The schema name the call was made with, or null when none was
  /// requested.
  final String? schemaName;
}

/// An [LlmChatClient] that returns scripted [ChatResult]s from a queue
/// and records every request it receives.
final class FakeLlmChatClient implements LlmChatClient {
  /// Creates a client with nothing queued and nothing recorded yet.
  new();

  final List<ChatResult> _queue = <ChatResult>[];

  /// Every request received, in call order.
  final List<RecordedChatRequest> requests = <RecordedChatRequest>[];

  /// The result returned once the queue set up by [enqueue] runs out.
  ChatResult fallback = const ChatFailed(reason: ChatFailureReason.badResponse);

  /// Adds [result] to the end of the queue [complete] draws from.
  void enqueue(ChatResult result) {
    _queue.add(result);
  }

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userPrompt,
    Map<String, Object?>? responseSchema,
    String? schemaName,
  }) async {
    requests.add(
      RecordedChatRequest(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        responseSchema: responseSchema,
        schemaName: schemaName,
      ),
    );
    if (_queue.isEmpty) return fallback;
    return _queue.removeAt(0);
  }
}
