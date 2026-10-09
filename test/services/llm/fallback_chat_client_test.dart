import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/llm/fallback_chat_client.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

import '../../fakes/fake_llm_chat_client.dart';

const ChatCompleted _primaryReply = ChatCompleted(
  content: '{"from": "primary"}',
  model: 'server-model',
);

const ChatCompleted _fallbackReply = ChatCompleted(
  content: '{"from": "fallback"}',
  model: 'device-model',
);

/// Sends one request with every argument set through [client].
Future<ChatResult> _send(LlmChatClient client) => client.complete(
  systemPrompt: 'system',
  userPrompt: 'user',
  responseSchema: const <String, Object?>{'type': 'object'},
  schemaName: 'menu',
  images: <ChatImagePart>[
    ChatImagePart(
      mimeType: ChatImagePart.png,
      bytes: Uint8List.fromList(<int>[1]),
    ),
  ],
);

void main() {
  group('FallbackChatClient (issue #331)', () {
    late FakeLlmChatClient primary;
    late FakeLlmChatClient fallback;
    late FallbackChatClient client;

    setUp(() {
      primary = FakeLlmChatClient();
      fallback = FakeLlmChatClient();
      client = FallbackChatClient(primary: primary, fallback: fallback);
    });

    test('a primary reply is returned; the fallback is not asked', () async {
      // Arrange
      primary.enqueue(_primaryReply);

      // Act
      final result = await _send(client);

      // Assert
      expect(result, _primaryReply);
      expect(fallback.requests, isEmpty);
    });

    for (final reason in <ChatFailureReason>[
      ChatFailureReason.notConfigured,
      ChatFailureReason.backendUnreachable,
      ChatFailureReason.timeout,
      ChatFailureReason.rateLimited,
    ]) {
      test(
        'a primary $reason sends the same request to the fallback',
        () async {
          // Arrange
          primary.enqueue(ChatFailed(reason: reason));
          fallback.enqueue(_fallbackReply);

          // Act
          final result = await _send(client);

          // Assert
          expect(result, _fallbackReply);
          expect(FallbackChatClient.shouldFallBack(reason), isTrue);
          final sent = fallback.requests.single;
          expect(sent.systemPrompt, 'system');
          expect(sent.userPrompt, 'user');
          expect(sent.responseSchema, <String, Object?>{'type': 'object'});
          expect(sent.schemaName, 'menu');
          expect(sent.images, hasLength(1));
        },
      );
    }

    for (final reason in <ChatFailureReason>[
      ChatFailureReason.offline,
      ChatFailureReason.badResponse,
      ChatFailureReason.apiKeyMissing,
      ChatFailureReason.apiKeyRejected,
    ]) {
      test('a primary $reason is returned as is', () async {
        // Arrange
        primary.enqueue(ChatFailed(reason: reason, statusCode: 502));

        // Act
        final result = await _send(client);

        // Assert
        expect(result, ChatFailed(reason: reason, statusCode: 502));
        expect(FallbackChatClient.shouldFallBack(reason), isFalse);
        expect(fallback.requests, isEmpty);
      });
    }

    test('when both fail, the primary failure is reported', () async {
      // Arrange
      primary.enqueue(
        const ChatFailed(reason: ChatFailureReason.backendUnreachable),
      );
      fallback.enqueue(
        const ChatFailed(reason: ChatFailureReason.apiKeyMissing),
      );

      // Act
      final result = await _send(client);

      // Assert
      expect(
        result,
        const ChatFailed(reason: ChatFailureReason.backendUnreachable),
      );
    });

    test('when the primary was only notConfigured, the fallback failure '
        'is reported', () async {
      // Arrange
      primary.enqueue(
        const ChatFailed(reason: ChatFailureReason.notConfigured),
      );
      fallback.enqueue(
        const ChatFailed(reason: ChatFailureReason.apiKeyRejected),
      );

      // Act
      final result = await _send(client);

      // Assert
      expect(
        result,
        const ChatFailed(reason: ChatFailureReason.apiKeyRejected),
      );
    });
  });
}
