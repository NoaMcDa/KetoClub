import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

import '../../fakes/fake_install_id_store.dart';
import 'llm_chat_client_contract.dart';

/// The backend base every test uses unless it is exercising the URL
/// composition itself.
final Uri _base = Uri.parse('https://api.ketoclub.test');

/// The install id the fake store answers with in every test.
const String _installId = '0123456789abcdef0123456789abcdef';

/// A response schema shape, matched to the one
/// `llm_chat_client_contract.dart` exercises.
const Map<String, Object?> _schema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
};

/// A backend success body carrying [content] from [model].
String _successBody({String content = 'ok', String model = 'served-model'}) =>
    jsonEncode(<String, Object?>{'content': content, 'model': model});

/// A backend error body naming [reason] with [statusCode].
String _errorBody(String reason, int statusCode) =>
    jsonEncode(<String, Object?>{'reason': reason, 'status_code': statusCode});

/// Builds a client over [transport], posting to [baseUrl].
BackendChatClient _build(
  MockClient transport, {
  Uri? baseUrl,
  bool noBase = false,
  FakeInstallIdStore? store,
  Duration timeout = const Duration(seconds: 120),
}) => BackendChatClient(
  client: transport,
  baseUrl: noBase ? null : (baseUrl ?? _base),
  installIdStore: store ?? FakeInstallIdStore(installId: _installId),
  timeout: timeout,
);

/// Builds a client whose transport always answers with [body] and
/// [status].
BackendChatClient _answering(String body, int status) =>
    _build(MockClient((_) async => http.Response(body, status)));

void main() {
  runLlmChatClientContract(
    'BackendChatClient',
    () => _answering(_successBody(), 200),
  );
  runLlmChatClientContract(
    'BackendChatClient (not configured)',
    () => _build(
      MockClient((_) async => http.Response(_successBody(), 200)),
      noBase: true,
    ),
  );

  group('BackendChatClient with no base URL', () {
    test('complete returns notConfigured without any I/O', () async {
      // Arrange
      var transportCalls = 0;
      final store = FakeInstallIdStore(installId: _installId);
      final client = _build(
        MockClient((_) async {
          transportCalls++;
          return http.Response(_successBody(), 200);
        }),
        noBase: true,
        store: store,
      );

      // Act
      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      // Assert
      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.notConfigured)),
      );
      expect(transportCalls, equals(0));
      expect(store.calls, equals(0));
    });
  });

  group('BackendChatClient request', () {
    test('posts to {base}/v1/chat', () async {
      // Arrange
      http.BaseRequest? captured;
      final client = _build(
        MockClient((request) async {
          captured = request;
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(captured!.method, equals('POST'));
      expect(
        captured!.url,
        equals(Uri.parse('https://api.ketoclub.test/v1/chat')),
      );
    });

    test(
      'posts to {base}/v1/chat when the base has a trailing slash',
      () async {
        // Arrange
        Uri? capturedUri;
        final client = _build(
          MockClient((request) async {
            capturedUri = request.url;
            return http.Response(_successBody(), 200);
          }),
          baseUrl: Uri.parse('https://api.ketoclub.test/'),
        );

        // Act
        await client.complete(systemPrompt: 's', userPrompt: 'u');

        // Assert
        expect(
          capturedUri,
          equals(Uri.parse('https://api.ketoclub.test/v1/chat')),
        );
      },
    );

    test('keeps a base path in front of /v1/chat', () async {
      // Arrange
      Uri? capturedUri;
      final client = _build(
        MockClient((request) async {
          capturedUri = request.url;
          return http.Response(_successBody(), 200);
        }),
        baseUrl: Uri.parse('https://example.test/ketoclub/'),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        capturedUri,
        equals(Uri.parse('https://example.test/ketoclub/v1/chat')),
      );
    });

    test('sends the install id and a JSON content type', () async {
      // Arrange
      Map<String, String>? capturedHeaders;
      final store = FakeInstallIdStore(installId: _installId);
      final client = _build(
        MockClient((request) async {
          capturedHeaders = request.headers;
          return http.Response(_successBody(), 200);
        }),
        store: store,
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(capturedHeaders!['X-KetoClub-Install-Id'], equals(_installId));
      expect(capturedHeaders!['Content-Type'], startsWith('application/json'));
      expect(store.calls, equals(1));
    });

    test('never sends an Authorization header', () async {
      // Arrange
      Map<String, String>? capturedHeaders;
      final client = _build(
        MockClient((request) async {
          capturedHeaders = request.headers;
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      // Assert
      final names = capturedHeaders!.keys.map((k) => k.toLowerCase());
      expect(names, isNot(contains('authorization')));
    });

    test('sends both prompts, the schema and its name when given', () async {
      // Arrange
      Object? capturedBody;
      final client = _build(
        MockClient((request) async {
          capturedBody = jsonDecode(request.body);
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(
        systemPrompt: 'the system',
        userPrompt: 'the user',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      // Assert
      expect(
        capturedBody,
        equals(<String, Object?>{
          'system_prompt': 'the system',
          'user_prompt': 'the user',
          'response_schema': _schema,
          'schema_name': 'menu_analysis',
        }),
      );
    });

    test('omits the schema and its name when not given', () async {
      // Arrange
      Object? capturedBody;
      final client = _build(
        MockClient((request) async {
          capturedBody = jsonDecode(request.body);
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(systemPrompt: 'the system', userPrompt: 'u');

      // Assert
      expect(
        capturedBody,
        equals(<String, Object?>{
          'system_prompt': 'the system',
          'user_prompt': 'u',
        }),
      );
    });

    test('sends one request per call, with no retry on failure', () async {
      // Arrange
      var transportCalls = 0;
      final client = _build(
        MockClient((_) async {
          transportCalls++;
          return http.Response(_errorBody('badResponse', 502), 502);
        }),
      );

      // Act
      await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        schemaName: 'menu_analysis',
      );

      // Assert
      expect(transportCalls, equals(1));
    });
  });

  group('BackendChatClient success', () {
    test('a 200 with content and model is ChatCompleted', () async {
      // Arrange
      final client = _answering(_successBody(content: '{"dishes":[]}'), 200);

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(
          const ChatCompleted(content: '{"dishes":[]}', model: 'served-model'),
        ),
      );
    });

    test('a 200 missing content is badResponse with the status', () async {
      // Arrange
      final client = _answering(
        jsonEncode(<String, Object?>{'model': 'served-model'}),
        200,
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

    test('a 200 missing model is badResponse with the status', () async {
      // Arrange
      final client = _answering(
        jsonEncode(<String, Object?>{'content': 'ok'}),
        200,
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

    test('a 200 with a non-string content is badResponse', () async {
      // Arrange
      final client = _answering(
        jsonEncode(<String, Object?>{'content': 42, 'model': 'm'}),
        200,
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

    test('a 200 whose body is not JSON is badResponse', () async {
      // Arrange
      final client = _answering('<html>', 200);

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

    test('a 200 whose body is a JSON list is badResponse', () async {
      // Arrange
      final client = _answering('[]', 200);

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
  });

  group('BackendChatClient error bodies', () {
    const wireCases = <(String, int, ChatFailureReason)>[
      ('notConfigured', 503, ChatFailureReason.notConfigured),
      ('offline', 502, ChatFailureReason.offline),
      ('timeout', 504, ChatFailureReason.timeout),
      ('rateLimited', 429, ChatFailureReason.rateLimited),
      ('badResponse', 502, ChatFailureReason.badResponse),
    ];

    for (final (name, status, expected) in wireCases) {
      test('reason "$name" with $status maps to $expected', () async {
        // Arrange
        final client = _answering(_errorBody(name, status), status);

        // Act
        final result = await client.complete(
          systemPrompt: 's',
          userPrompt: 'u',
        );

        // Assert
        expect(
          result,
          equals(ChatFailed(reason: expected, statusCode: status)),
        );
      });
    }

    test('every wire reason is covered above', () {
      // Arrange
      final covered = {for (final (_, _, reason) in wireCases) reason};

      // Act
      final clientOnly = ChatFailureReason.values.toSet().difference(covered);

      // Assert: only backendUnreachable is not a wire reason.
      expect(clientOnly, equals({ChatFailureReason.backendUnreachable}));
    });

    test('an unknown reason is badResponse with the status', () async {
      // Arrange
      final client = _answering(_errorBody('somethingNew', 500), 500);

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
    });

    test('the client-only backendUnreachable from the wire is '
        'badResponse', () async {
      // Arrange
      final client = _answering(_errorBody('backendUnreachable', 502), 502);

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 502,
          ),
        ),
      );
    });

    test('a non-string reason is badResponse with the status', () async {
      // Arrange
      final client = _answering(
        jsonEncode(<String, Object?>{'reason': 7, 'status_code': 503}),
        503,
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
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

    test('a FastAPI validation 422 is badResponse with the status', () async {
      // Arrange
      final client = _answering(
        jsonEncode(<String, Object?>{
          'detail': <Object?>[
            <String, Object?>{
              'loc': <Object?>['body', 'user_prompt'],
              'msg': 'Field required',
              'type': 'missing',
            },
          ],
        }),
        422,
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 422,
          ),
        ),
      );
    });

    test('a non-JSON 500 is badResponse with the status', () async {
      // Arrange
      final client = _answering('Internal Server Error', 500);

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
    });

    test('a 400 naming a wire reason still maps by name', () async {
      // Arrange: the backend answers 400 to an Authorization header with
      // `badResponse`; the status is carried as sent.
      final client = _answering(_errorBody('badResponse', 400), 400);

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
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
  });

  group('BackendChatClient transport failures', () {
    test('a ClientException is backendUnreachable, never offline', () async {
      // Arrange
      final client = _build(
        MockClient((request) async {
          throw http.ClientException('Connection refused', request.url);
        }),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.backendUnreachable)),
      );
    });

    test('a TimeoutException from the transport is timeout', () async {
      // Arrange
      final client = _build(
        MockClient((_) async {
          throw TimeoutException('slow');
        }),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.timeout)),
      );
    });

    test('a request exceeding the timeout is timeout', () {
      // Arrange & Act & Assert
      fakeAsync((async) {
        final client = _build(
          MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(seconds: 30),
        );

        ChatResult? result;
        unawaited(
          client
              .complete(systemPrompt: 's', userPrompt: 'u')
              .then((value) => result = value),
        );

        async.elapse(const Duration(seconds: 29));
        expect(result, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(
          result,
          equals(const ChatFailed(reason: ChatFailureReason.timeout)),
        );
      });
    });
  });

  group('BackendChatClient never leaks the body', () {
    test('a ChatFailed carries no text from the error body', () async {
      // Arrange
      const secret = 'upstream-said-something-private';
      final client = _answering(
        jsonEncode(<String, Object?>{
          'reason': 'badResponse',
          'status_code': 502,
          'extra': secret,
        }),
        502,
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(result.toString(), isNot(contains(secret)));
      expect(
        result,
        equals(
          const ChatFailed(
            reason: ChatFailureReason.badResponse,
            statusCode: 502,
          ),
        ),
      );
    });
  });
}
