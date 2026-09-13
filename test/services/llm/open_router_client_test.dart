import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/llm/open_router_client.dart';

import '../../fakes/fake_key_store.dart';
import 'llm_chat_client_contract.dart';

/// The key every test that needs one stores, unless it is exercising
/// "no key stored".
const String _key = 'sk-or-v1-test-key';

/// A response schema shape, matched to the one
/// `llm_chat_client_contract.dart` exercises so the contract's
/// "with a schema" calls exercise the strict `json_schema` path too.
const Map<String, Object?> _schema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
};

/// A minimal OpenRouter success body carrying [content] as the
/// assistant message.
String _successBody(String content) => jsonEncode(<String, Object?>{
  'choices': <Object?>[
    <String, Object?>{
      'message': <String, Object?>{'role': 'assistant', 'content': content},
    },
  ],
});

/// Builds a client whose transport always answers 200 with [content],
/// storing [seed] as the key (a key is stored by default).
OpenRouterClient _buildSuccessClient({
  String content = 'ok',
  String? seed = _key,
}) => OpenRouterClient(
  client: MockClient((_) async => http.Response(_successBody(content), 200)),
  keyStore: FakeKeyStore(seed: seed),
);

void main() {
  runLlmChatClientContract('OpenRouterClient', _buildSuccessClient);

  group('OpenRouterClient', () {
    test('rejectsRequestShape is true for 400, 404 and 422', () {
      // Arrange & Act & Assert
      expect(OpenRouterClient.rejectsRequestShape(400), isTrue);
      expect(OpenRouterClient.rejectsRequestShape(404), isTrue);
      expect(OpenRouterClient.rejectsRequestShape(422), isTrue);
    });

    test('rejectsRequestShape is false for 401, 403, 429, 500 and 200', () {
      // Arrange & Act & Assert
      expect(OpenRouterClient.rejectsRequestShape(401), isFalse);
      expect(OpenRouterClient.rejectsRequestShape(403), isFalse);
      expect(OpenRouterClient.rejectsRequestShape(429), isFalse);
      expect(OpenRouterClient.rejectsRequestShape(500), isFalse);
      expect(OpenRouterClient.rejectsRequestShape(200), isFalse);
    });

    test('documentedFallbackModels has at least two entries', () {
      // Arrange & Act & Assert
      expect(
        OpenRouterClient.documentedFallbackModels.length,
        greaterThanOrEqualTo(2),
      );
    });

    test('complete sends the exact OpenRouter chat completions URL', () async {
      // Arrange
      Uri? capturedUri;
      final client = OpenRouterClient(
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response(_successBody('ok'), 200);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        capturedUri,
        equals(Uri.parse('https://openrouter.ai/api/v1/chat/completions')),
      );
    });

    test(
      'complete sends the Authorization Bearer header with the stored key',
      () async {
        // Arrange
        Map<String, String>? capturedHeaders;
        final client = OpenRouterClient(
          client: MockClient((request) async {
            capturedHeaders = request.headers;
            return http.Response(_successBody('ok'), 200);
          }),
          keyStore: FakeKeyStore(seed: _key),
        );

        // Act
        await client.complete(systemPrompt: 's', userPrompt: 'u');

        // Assert
        expect(capturedHeaders!['Authorization'], equals('Bearer $_key'));
      },
    );

    test('complete sends HTTP-Referer and X-Title headers identifying '
        'KetoClub', () async {
      // Arrange
      Map<String, String>? capturedHeaders;
      final client = OpenRouterClient(
        client: MockClient((request) async {
          capturedHeaders = request.headers;
          return http.Response(_successBody('ok'), 200);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(capturedHeaders!['HTTP-Referer'], isNotEmpty);
      expect(capturedHeaders!['X-Title'], equals('KetoClub'));
    });

    test('complete never sends the key in the request body', () async {
      // Arrange
      String? capturedBody;
      final client = OpenRouterClient(
        client: MockClient((request) async {
          capturedBody = request.body;
          return http.Response(_successBody('ok'), 200);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      // Assert
      expect(capturedBody, isNotNull);
      expect(capturedBody!.contains(_key), isFalse);
      final decoded = jsonDecode(capturedBody!) as Map<String, Object?>;
      expect(decoded.containsKey('key'), isFalse);
      expect(decoded.containsKey('api_key'), isFalse);
      expect(decoded.containsKey('Authorization'), isFalse);
    });

    test('complete sends a strict json_schema response_format with the given '
        'schema and name, plus max_tokens', () async {
      // Arrange
      String? capturedBody;
      final client = OpenRouterClient(
        client: MockClient((request) async {
          capturedBody = request.body;
          return http.Response(_successBody('ok'), 200);
        }),
        keyStore: FakeKeyStore(seed: _key),
        maxTokens: 4242,
      );

      // Act
      await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      // Assert
      final decoded = jsonDecode(capturedBody!) as Map<String, Object?>;
      expect(decoded['max_tokens'], equals(4242));
      final format = decoded['response_format']! as Map<String, Object?>;
      expect(format['type'], equals('json_schema'));
      final jsonSchema = format['json_schema']! as Map<String, Object?>;
      expect(jsonSchema['name'], equals('menu_analysis'));
      expect(jsonSchema['strict'], isTrue);
      expect(jsonSchema['schema'], equals(_schema));
    });

    test(
      'complete sends no response_format when no schema was requested',
      () async {
        // Arrange
        String? capturedBody;
        final client = OpenRouterClient(
          client: MockClient((request) async {
            capturedBody = request.body;
            return http.Response(_successBody('ok'), 200);
          }),
          keyStore: FakeKeyStore(seed: _key),
        );

        // Act
        await client.complete(systemPrompt: 's', userPrompt: 'u');

        // Assert
        final decoded = jsonDecode(capturedBody!) as Map<String, Object?>;
        expect(decoded.containsKey('response_format'), isFalse);
      },
    );

    /// Runs a schema request whose first attempt answers [firstStatus],
    /// asserting exactly one fallback re-send happened and that the two
    /// request bodies differ only in `response_format`
    /// (`m16_structured_output_fix.md`). Returns the eventual result.
    Future<ChatResult> assertsExactlyOneShapeFallback(int firstStatus) async {
      final bodies = <String>[];
      final client = OpenRouterClient(
        client: MockClient((request) async {
          bodies.add(request.body);
          if (bodies.length == 1) {
            return http.Response('{}', firstStatus);
          }
          return http.Response(_successBody('ok'), 200);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      expect(bodies, hasLength(2), reason: 'status $firstStatus');
      final first = jsonDecode(bodies[0]) as Map<String, Object?>;
      final second = jsonDecode(bodies[1]) as Map<String, Object?>;
      expect(
        first['response_format'],
        equals(<String, Object?>{
          'type': 'json_schema',
          'json_schema': <String, Object?>{
            'name': 'menu_analysis',
            'strict': true,
            'schema': _schema,
          },
        }),
      );
      expect(
        second['response_format'],
        equals(<String, Object?>{'type': 'json_object'}),
      );
      first.remove('response_format');
      second.remove('response_format');
      expect(second, equals(first), reason: 'status $firstStatus');
      return result;
    }

    test('complete re-sends once with json_object when the first attempt '
        'answers 400', () async {
      // Arrange, Act & Assert
      final result = await assertsExactlyOneShapeFallback(400);
      expect(result, isA<ChatCompleted>());
    });

    test('complete re-sends once with json_object when the first attempt '
        'answers 404', () async {
      // Arrange, Act & Assert
      final result = await assertsExactlyOneShapeFallback(404);
      expect(result, isA<ChatCompleted>());
    });

    test('complete re-sends once with json_object when the first attempt '
        'answers 422', () async {
      // Arrange, Act & Assert
      final result = await assertsExactlyOneShapeFallback(422);
      expect(result, isA<ChatCompleted>());
    });

    test('complete maps a still-failing status after the fallback to '
        'badResponse', () async {
      // Arrange
      var callCount = 0;
      final client = OpenRouterClient(
        client: MockClient((_) async {
          callCount++;
          return http.Response('{}', 400);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      // Assert
      expect(callCount, equals(2));
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 400,
          ),
        ),
      );
    });

    test('complete maps a ClientException on the fallback attempt itself '
        'to offline', () async {
      // Arrange
      var callCount = 0;
      final client = OpenRouterClient(
        client: MockClient((request) async {
          callCount++;
          if (callCount == 1) return http.Response('{}', 400);
          throw http.ClientException('Connection failed', request.url);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      // Assert
      expect(callCount, equals(2));
      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.offline)),
      );
    });

    test('complete maps a timeout on the fallback attempt itself to '
        'timeout', () {
      // Arrange & Act & Assert
      fakeAsync((async) {
        var callCount = 0;
        final client = OpenRouterClient(
          client: MockClient((_) {
            callCount++;
            if (callCount == 1) {
              return Future<http.Response>.value(http.Response('{}', 400));
            }
            return Completer<http.Response>().future;
          }),
          keyStore: FakeKeyStore(seed: _key),
        );

        ChatResult? result;
        unawaited(
          client
              .complete(
                systemPrompt: 's',
                userPrompt: 'u',
                responseSchema: _schema,
                schemaName: 'menu_analysis',
              )
              .then((value) => result = value),
        );

        async.elapse(const Duration(seconds: 120));

        expect(callCount, equals(2));
        expect(
          result,
          equals(const ChatFailed(reason: ChatFailureReason.timeout)),
        );
      });
    });

    /// Runs a schema request that always answers [status], asserting it
    /// is sent exactly once (no shape-fallback retry) and returning the
    /// result.
    Future<ChatResult> sentExactlyOnce(int status, {String body = '{}'}) async {
      var callCount = 0;
      final client = OpenRouterClient(
        client: MockClient((_) async {
          callCount++;
          return http.Response(body, status);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      expect(callCount, equals(1), reason: 'status $status');
      return result;
    }

    test('complete sends a 401 response exactly once', () async {
      // Arrange, Act & Assert
      final result = await sentExactlyOnce(401);
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.unauthorised,
            statusCode: 401,
          ),
        ),
      );
    });

    test('complete sends a 403 response exactly once', () async {
      // Arrange, Act & Assert
      final result = await sentExactlyOnce(403);
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.unauthorised,
            statusCode: 403,
          ),
        ),
      );
    });

    test('complete sends a 429 response exactly once', () async {
      // Arrange, Act & Assert
      final result = await sentExactlyOnce(429);
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.rateLimited,
            statusCode: 429,
          ),
        ),
      );
    });

    test('complete sends a 500 response exactly once', () async {
      // Arrange, Act & Assert
      final result = await sentExactlyOnce(500);
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 500,
          ),
        ),
      );
    });

    test('complete sends a 503 response exactly once', () async {
      // Arrange, Act & Assert
      final result = await sentExactlyOnce(503);
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 503,
          ),
        ),
      );
    });

    test('complete sends a request with no schema exactly once even on a '
        '400', () async {
      // Arrange
      var callCount = 0;
      final client = OpenRouterClient(
        client: MockClient((_) async {
          callCount++;
          return http.Response('{}', 400);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(callCount, equals(1));
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 400,
          ),
        ),
      );
    });

    test('complete maps a ClientException to offline', () async {
      // Arrange
      final client = OpenRouterClient(
        client: MockClient((request) async {
          throw http.ClientException('Connection failed', request.url);
        }),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.offline)),
      );
    });

    test('complete maps a request exceeding the timeout to timeout, '
        'never offline', () {
      // Arrange & Act & Assert
      fakeAsync((async) {
        final client = OpenRouterClient(
          client: MockClient((_) => Completer<http.Response>().future),
          keyStore: FakeKeyStore(seed: _key),
        );

        ChatResult? result;
        unawaited(
          client
              .complete(systemPrompt: 's', userPrompt: 'u')
              .then((value) => result = value),
        );

        async.elapse(const Duration(seconds: 120));

        expect(
          result,
          equals(const ChatFailed(reason: ChatFailureReason.timeout)),
        );
      });
    });

    test('complete does not resolve before the timeout elapses', () {
      // Arrange & Act & Assert
      fakeAsync((async) {
        final client = OpenRouterClient(
          client: MockClient((_) => Completer<http.Response>().future),
          keyStore: FakeKeyStore(seed: _key),
        );

        ChatResult? result;
        unawaited(
          client
              .complete(systemPrompt: 's', userPrompt: 'u')
              .then((value) => result = value),
        );

        async.elapse(const Duration(seconds: 119));

        expect(result, isNull);
      });
    });

    test('complete maps a 2xx non-JSON body to badResponse', () async {
      // Arrange
      final client = OpenRouterClient(
        client: MockClient((_) async => http.Response('<html>', 200)),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 200,
          ),
        ),
      );
    });

    test('complete maps a 2xx body with no assistant message content to '
        'badResponse', () async {
      // Arrange
      final client = OpenRouterClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{'choices': <Object?>[]}),
            200,
          ),
        ),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 200,
          ),
        ),
      );
    });

    test('a ChatFailed from a 500 with a secret-looking body never carries '
        'that body', () async {
      // Arrange
      const secret = 'sk-or-v1-super-secret-leaked-token-0000000000';
      final client = OpenRouterClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'message': 'invalid request',
                'request_headers': <String, Object?>{
                  'Authorization': 'Bearer $secret',
                },
              },
            }),
            500,
          ),
        ),
        keyStore: FakeKeyStore(seed: _key),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 500,
          ),
        ),
      );
      expect(result.toString().contains(secret), isFalse);
    });

    test('complete returns unauthorised when no key is stored', () async {
      // Arrange
      var called = false;
      final client = OpenRouterClient(
        client: MockClient((_) async {
          called = true;
          return http.Response(_successBody('ok'), 200);
        }),
        keyStore: FakeKeyStore(),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(called, isFalse);
      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.unauthorised)),
      );
    });

    test('complete returns ChatCompleted with the content and model on '
        'success', () async {
      // Arrange
      final client = OpenRouterClient(
        client: MockClient(
          (_) async => http.Response(_successBody('the analysis'), 200),
        ),
        keyStore: FakeKeyStore(seed: _key),
        model: 'a/model:free',
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(
          const ChatCompleted(content: 'the analysis', model: 'a/model:free'),
        ),
      );
    });
  });
}
