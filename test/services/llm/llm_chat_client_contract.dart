import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

/// A response schema shape, used only to exercise the "schema requested"
/// call form; its content is irrelevant to the contract.
const Map<String, Object?> _schema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
};

/// Asserts the [LlmChatClient] contract against the implementation
/// [build] returns. Call this from each implementation's own test file —
/// including the fake — passing a factory for a fresh instance
/// (architecture.md §18.1, Liskov).
void runLlmChatClientContract(String name, LlmChatClient Function() build) {
  group('$name (LlmChatClient contract)', () {
    test('complete without a schema resolves to a ChatResult', () async {
      final client = build();

      final result = await client.complete(
        systemPrompt: 'system',
        userPrompt: 'user',
      );

      expect(result, isA<ChatResult>());
    });

    test('complete with a schema resolves to a ChatResult', () async {
      final client = build();

      final result = await client.complete(
        systemPrompt: 'system',
        userPrompt: 'user',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      expect(result, isA<ChatResult>());
    });

    test('complete without a schema never throws', () async {
      final client = build();

      await expectLater(
        client.complete(systemPrompt: 'system', userPrompt: 'user'),
        completes,
      );
    });

    test('complete with a schema never throws', () async {
      final client = build();

      await expectLater(
        client.complete(
          systemPrompt: 'system',
          userPrompt: 'user',
          responseSchema: _schema,
          schemaName: 'menu_analysis',
        ),
        completes,
      );
    });

    test(
      'complete resolves to exactly a ChatCompleted or a ChatFailed',
      () async {
        final client = build();

        final result = await client.complete(
          systemPrompt: 'system',
          userPrompt: 'user',
        );

        // Exhaustive: ChatResult is sealed over exactly these two cases,
        // so this switch needs no fallback branch to compile.
        final kind = switch (result) {
          ChatCompleted() => 'completed',
          ChatFailed() => 'failed',
        };
        expect(kind, anyOf('completed', 'failed'));
      },
    );

    test(
      'a ChatFailed result carries a status code or null, never free text',
      () async {
        final client = build();

        final result = await client.complete(
          systemPrompt: 'system',
          userPrompt: 'user',
        );

        if (result case final ChatFailed failed) {
          expect(failed.statusCode, anyOf(isNull, isA<int>()));
        }
      },
    );
  });
}
