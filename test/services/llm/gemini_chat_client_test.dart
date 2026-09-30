import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/services/llm/gemini_chat_client.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';

import '../../fakes/fake_api_key_store.dart';
import 'llm_chat_client_contract.dart';

/// The key every test saves unless it is exercising the key itself.
const String _key = 'AIza-test-key-0123456789';

/// A strict schema in the shape `MenuAnalysisPrompt` sends, small enough
/// to read: a nullable union, `additionalProperties`, and nesting.
const Map<String, Object?> _schema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <Object?>['dishes'],
  'properties': <String, Object?>{
    'dishes': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{
          'id': <String, Object?>{'type': 'string'},
          'net_carbs': <String, Object?>{
            'type': <Object?>['number', 'null'],
          },
        },
      },
    },
  },
};

/// A Gemini success body whose first candidate carries [text].
String _successBody({
  String text = '{"dishes":[]}',
  String finishReason = 'STOP',
  String? modelVersion = 'gemini-3.5-flash-001',
}) => jsonEncode(<String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'finishReason': finishReason,
      'content': <String, Object?>{
        'role': 'model',
        'parts': <Object?>[
          <String, Object?>{'text': text},
        ],
      },
    },
  ],
  'modelVersion': ?modelVersion,
});

/// Gemini's error body for an invalid key, exactly as Google returned it
/// on 2026-09-28 to `generateContent` with `x-goog-api-key: not-a-real-key`
/// — recorded, not hand-built.
final String _invalidKeyBody = jsonEncode(<String, Object?>{
  'error': <String, Object?>{
    'code': 400,
    'message': 'API key not valid. Please pass a valid API key.',
    'status': 'INVALID_ARGUMENT',
    'details': <Object?>[
      <String, Object?>{
        '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
        'reason': 'API_KEY_INVALID',
        'domain': 'googleapis.com',
        'metadata': <String, Object?>{
          'service': 'generativelanguage.googleapis.com',
        },
      },
      <String, Object?>{
        '@type': 'type.googleapis.com/google.rpc.LocalizedMessage',
        'locale': 'en-US',
        'message': 'API key not valid. Please pass a valid API key.',
      },
    ],
  },
});

/// Gemini's error body for a request it could not use.
final String _badRequestBody = jsonEncode(<String, Object?>{
  'error': <String, Object?>{
    'code': 400,
    'message': 'Invalid JSON payload received.',
    'status': 'INVALID_ARGUMENT',
  },
});

/// A two-page menu: a WebP photograph and a PDF, in that order.
final List<ChatImagePart> _pages = <ChatImagePart>[
  ChatImagePart(
    mimeType: ChatImagePart.webp,
    bytes: Uint8List.fromList(utf8.encode('RIFF page one')),
  ),
  ChatImagePart(
    mimeType: ChatImagePart.pdf,
    bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 menu')),
  ),
];

/// [_pages] as the `inline_data` parts Gemini should receive.
const List<Object?> _inlinePages = <Object?>[
  <String, Object?>{
    'inline_data': <String, Object?>{
      'mime_type': 'image/webp',
      'data': 'UklGRiBwYWdlIG9uZQ==',
    },
  },
  <String, Object?>{
    'inline_data': <String, Object?>{
      'mime_type': 'application/pdf',
      'data': 'JVBERi0xLjQgbWVudQ==',
    },
  },
];

/// Builds a client over [transport], with [key] saved unless it is null.
GeminiChatClient _build(
  MockClient transport, {
  String? key = _key,
  Duration timeout = const Duration(seconds: 120),
}) => GeminiChatClient(
  client: transport,
  apiKeyStore: FakeApiKeyStore(seed: key),
  timeout: timeout,
);

/// Builds a client whose transport always answers with [body] and
/// [status].
GeminiChatClient _answering(String body, int status) =>
    _build(MockClient((_) async => http.Response(body, status)));

/// The JSON body of [request], decoded.
Map<String, Object?> _bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;

/// The `generationConfig` of [request]'s body.
Map<String, Object?> _configOf(http.Request request) =>
    _bodyOf(request)['generationConfig']! as Map<String, Object?>;

void main() {
  runLlmChatClientContract(
    'GeminiChatClient',
    () => _answering(_successBody(), 200),
  );
  runLlmChatClientContract(
    'GeminiChatClient (no key)',
    () => _build(
      MockClient((_) async => http.Response(_successBody(), 200)),
      key: null,
    ),
  );

  group('GeminiChatClient with no usable key', () {
    for (final (label, key) in const <(String, String?)>[
      ('no key saved', null),
      ('an empty key', ''),
      ('a whitespace-only key', '   '),
    ]) {
      test('$label is apiKeyMissing without any request', () async {
        // Arrange
        var requests = 0;
        final client = _build(
          MockClient((_) async {
            requests++;
            return http.Response(_successBody(), 200);
          }),
          key: key,
        );

        // Act
        final result = await client.complete(
          systemPrompt: 's',
          userPrompt: 'u',
        );

        // Assert
        expect(
          result,
          equals(const ChatFailed(reason: ChatFailureReason.apiKeyMissing)),
        );
        expect(requests, 0);
      });
    }
  });

  group('GeminiChatClient with a key no header can carry', () {
    for (final (label, key) in const <(String, String)>[
      ('an inner space', 'AIza key'),
      ('a line break', 'AIza\nkey'),
      ('a non-ASCII character', 'AIza-מפתח'),
    ]) {
      test('$label is apiKeyRejected without any request', () async {
        // Arrange
        var requests = 0;
        final client = _build(
          MockClient((_) async {
            requests++;
            return http.Response(_successBody(), 200);
          }),
          key: key,
        );

        // Act
        final result = await client.complete(
          systemPrompt: 's',
          userPrompt: 'u',
        );

        // Assert
        expect(
          result,
          equals(const ChatFailed(reason: ChatFailureReason.apiKeyRejected)),
        );
        expect(requests, 0);
      });
    }
  });

  group('GeminiChatClient request', () {
    test("posts to Google's generateContent for the default model", () async {
      // Arrange
      late http.Request sent;
      final client = _build(
        MockClient((request) async {
          sent = request;
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(sent.method, 'POST');
      expect(
        sent.url,
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          'gemini-3.5-flash:generateContent',
        ),
      );
    });

    test('names a different model when given one', () {
      // Arrange
      final client = GeminiChatClient(
        client: MockClient((_) async => http.Response('', 200)),
        apiKeyStore: FakeApiKeyStore(seed: _key),
        model: 'gemini-2.5-pro',
      );

      // Act & Assert
      expect(
        client.endpoint.path,
        '/v1beta/models/gemini-2.5-pro:'
        'generateContent',
      );
    });

    test('sends the key only as x-goog-api-key, never in the URL', () async {
      // Arrange
      late http.Request sent;
      final client = _build(
        MockClient((request) async {
          sent = request;
          return http.Response(_successBody(), 200);
        }),
        key: '  $_key  ',
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert: trimmed, in the header, and nowhere else.
      expect(sent.headers['x-goog-api-key'], _key);
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(sent.url.toString(), isNot(contains(_key)));
      expect(sent.body, isNot(contains(_key)));
      expect(sent.headers.keys, isNot(contains('authorization')));
    });

    test('never sends a KetoClub install id', () async {
      // Arrange
      late http.Request sent;
      final client = _build(
        MockClient((request) async {
          sent = request;
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert: this request goes to Google, not to KetoClub's backend.
      expect(
        sent.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('x-ketoclub-install-id')),
      );
    });

    test('sends both prompts and the generation config', () async {
      // Arrange
      late http.Request sent;
      final client = _build(
        MockClient((request) async {
          sent = request;
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(systemPrompt: 'the system', userPrompt: 'menu');

      // Assert
      final body = _bodyOf(sent);
      expect(
        body['system_instruction'],
        equals(<String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': 'the system'},
          ],
        }),
      );
      expect(
        body['contents'],
        equals(<Object?>[
          <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': 'menu'},
            ],
          },
        ]),
      );
      expect(
        _configOf(sent),
        equals(<String, Object?>{
          'responseMimeType': 'application/json',
          'maxOutputTokens': 8192,
          'temperature': 0,
          'thinkingConfig': <String, Object?>{'thinkingBudget': 0},
        }),
      );
    });

    test('sends the schema converted to Gemini form when given', () async {
      // Arrange
      late http.Request sent;
      final client = _build(
        MockClient((request) async {
          sent = request;
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

      // Assert: converted, and the name goes nowhere (Gemini has none).
      expect(_configOf(sent)['responseSchema'], toGeminiSchema(_schema));
      expect(sent.body, isNot(contains('menu_analysis')));
    });

    test('omits responseSchema when no schema is given', () async {
      // Arrange
      late http.Request sent;
      final client = _build(
        MockClient((request) async {
          sent = request;
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(_configOf(sent).containsKey('responseSchema'), isFalse);
    });

    test('sends each image as an inline_data part after the text part, in '
        'order', () async {
      // Arrange
      late http.Request sent;
      final client = _build(
        MockClient((request) async {
          sent = request;
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'menu',
        images: _pages,
      );

      // Assert
      expect(result, isA<ChatCompleted>());
      expect(
        _bodyOf(sent)['contents'],
        equals(<Object?>[
          <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': 'menu'},
              ..._inlinePages,
            ],
          },
        ]),
      );
      expect(sent.headers[GeminiChatClient.apiKeyHeader], equals(_key));
    });

    test('a text-only body is byte for byte the pre-image body', () async {
      // Arrange
      final bodies = <String>[];
      final client = _build(
        MockClient((request) async {
          bodies.add(request.body);
          return http.Response(_successBody(), 200);
        }),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');
      await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        // Passing the default explicitly is this test's point: an empty
        // list must send exactly what omitting it sends.
        // ignore: avoid_redundant_argument_values
        images: const <ChatImagePart>[],
      );

      // Assert
      final expected = <String>[
        '{"system_instruction":{"parts":[{"text":"s"}]},',
        '"contents":[{"role":"user","parts":[{"text":"u"}]}],',
        '"generationConfig":{"responseMimeType":"application/json",',
        '"maxOutputTokens":8192,"temperature":0,',
        '"thinkingConfig":{"thinkingBudget":0}}}',
      ].join();
      expect(bodies, equals(<String>[expected, expected]));
    });
  });

  group('GeminiChatClient success', () {
    test('a 200 with a STOP candidate is ChatCompleted', () async {
      // Arrange
      final client = _answering(_successBody(text: '{"a":1}'), 200);

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(
          const ChatCompleted(
            content: '{"a":1}',
            model: 'gemini-3.5-flash-001',
          ),
        ),
      );
    });

    test('falls back to the configured model with no modelVersion', () async {
      // Arrange
      final client = _answering(_successBody(modelVersion: null), 200);

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect((result as ChatCompleted).model, 'gemini-3.5-flash');
    });

    test('decodes a Hebrew reply as UTF-8 even with no content type', () async {
      // Arrange: with no content type, http.Response.body would fall back
      // to Latin-1 here.
      final bytes = utf8.encode(_successBody(text: '{"name":"סלט"}'));
      final client = _build(
        MockClient((_) async => http.Response.bytes(bytes, 200)),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect((result as ChatCompleted).content, '{"name":"סלט"}');
    });

    test('a 200 whose bytes are not UTF-8 is badResponse', () async {
      // Arrange
      final client = _build(
        MockClient((_) async => http.Response.bytes(<int>[0xff, 0xfe], 200)),
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

    test('joins text parts and skips thought parts', () async {
      // Arrange
      final body = jsonEncode(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'finishReason': 'STOP',
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': 'thinking', 'thought': true},
                <String, Object?>{'text': '{"dishes":'},
                <String, Object?>{'inlineData': 'ignored'},
                <String, Object?>{'text': '[]}'},
              ],
            },
          },
        ],
      });
      final client = _answering(body, 200);

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect((result as ChatCompleted).content, '{"dishes":[]}');
    });
  });

  group('GeminiChatClient unusable 200s are badResponse', () {
    final cases = <(String, String)>[
      ('a MAX_TOKENS candidate', _successBody(finishReason: 'MAX_TOKENS')),
      ('a SAFETY candidate', _successBody(finishReason: 'SAFETY')),
      ('an empty text', _successBody(text: '')),
      (
        'no candidates',
        jsonEncode(<String, Object?>{'candidates': <Object?>[]}),
      ),
      ('a missing candidates field', jsonEncode(<String, Object?>{})),
      (
        'a candidate that is not an object',
        jsonEncode(<String, Object?>{
          'candidates': <Object?>['x'],
        }),
      ),
      (
        'a candidate with no content',
        jsonEncode(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{'finishReason': 'STOP'},
          ],
        }),
      ),
      (
        'content with no parts list',
        jsonEncode(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'finishReason': 'STOP',
              'content': <String, Object?>{'parts': 'x'},
            },
          ],
        }),
      ),
      ('a body that is not JSON', '<html>'),
      ('a body that is a JSON list', '[]'),
    ];

    for (final (label, body) in cases) {
      test(label, () async {
        // Arrange
        final client = _answering(body, 200);

        // Act
        final result = await client.complete(
          systemPrompt: 's',
          userPrompt: 'u',
        );

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
    }
  });

  group('GeminiChatClient error statuses', () {
    final cases = <(String, int, String, ChatFailureReason)>[
      ('401', 401, '{}', ChatFailureReason.apiKeyRejected),
      ('403', 403, '{}', ChatFailureReason.apiKeyRejected),
      (
        'a 400 naming an invalid key',
        400,
        _invalidKeyBody,
        ChatFailureReason.apiKeyRejected,
      ),
      ('429', 429, '{}', ChatFailureReason.rateLimited),
      ('500', 500, '{}', ChatFailureReason.badResponse),
      ('503', 503, 'not json', ChatFailureReason.badResponse),
      ('404', 404, '{}', ChatFailureReason.badResponse),
      (
        'a 400 that is not about the key',
        400,
        _badRequestBody,
        ChatFailureReason.badResponse,
      ),
    ];

    for (final (label, status, body, expected) in cases) {
      test('$label maps to ${expected.name}', () async {
        // Arrange
        final client = _answering(body, status);

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

    for (final (label, error) in <(String, Map<String, Object?>)>[
      ('its status', <String, Object?>{'status': 'API_KEY_INVALID'}),
      ('its message marker', <String, Object?>{'message': 'API_KEY_INVALID'}),
      ('its plain message', <String, Object?>{'message': 'API Key not VALID'}),
    ]) {
      test('a 400 naming an invalid key in $label is apiKeyRejected', () async {
        // Arrange
        final body = jsonEncode(<String, Object?>{'error': error});
        final client = _answering(body, 400);

        // Act
        final result = await client.complete(
          systemPrompt: 's',
          userPrompt: 'u',
        );

        // Assert
        expect(
          result,
          equals(
            const ChatFailed(
              reason: ChatFailureReason.apiKeyRejected,
              statusCode: 400,
            ),
          ),
        );
      });
    }

    for (final (label, body) in <(String, String)>[
      ('a list', '[]'),
      ('an error that is not an object', '{"error":"x"}'),
      ('details that are not a list', '{"error":{"details":"x"}}'),
      ('a detail that is not an object', '{"error":{"details":["x"]}}'),
    ]) {
      test('a 400 whose body is $label is not a key rejection', () async {
        // Arrange
        final client = _answering(body, 400);

        // Act
        final result = await client.complete(
          systemPrompt: 's',
          userPrompt: 'u',
        );

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
    }
  });

  group('GeminiChatClient retry without the schema', () {
    test('a non-key 400 with a schema is re-sent once without it', () async {
      // Arrange
      final sent = <http.Request>[];
      final client = _build(
        MockClient((request) async {
          sent.add(request);
          return sent.length == 1
              ? http.Response(_badRequestBody, 400)
              : http.Response(_successBody(), 200);
        }),
      );

      // Act
      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
      );

      // Assert
      expect(result, isA<ChatCompleted>());
      expect(sent, hasLength(2));
      expect(_configOf(sent[0]).containsKey('responseSchema'), isTrue);
      expect(_configOf(sent[1]).containsKey('responseSchema'), isFalse);
      expect(_configOf(sent[1])['responseMimeType'], 'application/json');
    });

    test('the retry re-sends the images unchanged', () async {
      // Arrange
      final sent = <http.Request>[];
      final client = _build(
        MockClient((request) async {
          sent.add(request);
          return sent.length == 1
              ? http.Response(_badRequestBody, 400)
              : http.Response(_successBody(), 200);
        }),
      );

      // Act
      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
        images: _pages,
      );

      // Assert
      expect(result, isA<ChatCompleted>());
      expect(sent, hasLength(2));
      expect(_configOf(sent[1]).containsKey('responseSchema'), isFalse);
      expect(
        _bodyOf(sent[1])['contents'],
        equals(_bodyOf(sent[0])['contents']),
      );
      final parts =
          (_bodyOf(sent[1])['contents']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(parts['parts'], hasLength(3));
    });

    test('a second 400 is not re-sent again', () async {
      // Arrange
      var requests = 0;
      final client = _build(
        MockClient((_) async {
          requests++;
          return http.Response(_badRequestBody, 400);
        }),
      );

      // Act
      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
      );

      // Assert
      expect(requests, 2);
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

    test('a timeout on the retry is timeout', () async {
      // Arrange
      var requests = 0;
      final client = _build(
        MockClient((_) async {
          requests++;
          if (requests == 1) return http.Response(_badRequestBody, 400);
          throw TimeoutException('slow');
        }),
      );

      // Act
      final result = await client.complete(
        systemPrompt: 's',
        userPrompt: 'u',
        responseSchema: _schema,
      );

      // Assert
      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.timeout)),
      );
    });

    final notRetried = <(String, int, String)>[
      ('an invalid-key 400', 400, _invalidKeyBody),
      ('a 401', 401, '{}'),
      ('a 403', 403, '{}'),
      ('a 429', 429, '{}'),
      ('a 500', 500, '{}'),
    ];
    for (final (label, status, body) in notRetried) {
      test('$label with a schema is never re-sent', () async {
        // Arrange
        var requests = 0;
        final client = _build(
          MockClient((_) async {
            requests++;
            return http.Response(body, status);
          }),
        );

        // Act
        await client.complete(
          systemPrompt: 's',
          userPrompt: 'u',
          responseSchema: _schema,
        );

        // Assert
        expect(requests, 1);
      });
    }

    test('a non-key 400 without a schema is never re-sent', () async {
      // Arrange
      var requests = 0;
      final client = _build(
        MockClient((_) async {
          requests++;
          return http.Response(_badRequestBody, 400);
        }),
      );

      // Act
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(requests, 1);
    });
  });

  group('GeminiChatClient transport failures', () {
    test('a ClientException is offline: there is no server between', () async {
      // Arrange
      final client = _build(
        MockClient((_) async => throw http.ClientException('no route')),
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(
        result,
        equals(const ChatFailed(reason: ChatFailureReason.offline)),
      );
    });

    test('a TimeoutException from the transport is timeout', () async {
      // Arrange
      final client = _build(
        MockClient((_) async => throw TimeoutException('slow')),
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
      fakeAsync((async) {
        // Arrange
        final client = _build(
          MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(seconds: 30),
        );
        ChatResult? result;

        // Act
        unawaited(
          client
              .complete(systemPrompt: 's', userPrompt: 'u')
              .then((value) => result = value),
        );
        async.elapse(const Duration(seconds: 29));

        // Assert
        expect(result, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(
          result,
          equals(const ChatFailed(reason: ChatFailureReason.timeout)),
        );
      });
    });
  });

  group('GeminiChatClient never leaks the key or the body', () {
    test('a ChatFailed carries no text from the error body', () async {
      // Arrange
      const secret = 'upstream-said-something-private';
      final client = _answering(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{'message': secret},
        }),
        500,
      );

      // Act
      final result = await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert
      expect(result.toString(), isNot(contains(secret)));
    });

    test('toString names the model and never the key', () {
      // Arrange
      final client = _answering(_successBody(), 200);

      // Act & Assert
      expect(client.toString(), contains('gemini-3.5-flash'));
      expect(client.toString(), isNot(contains(_key)));
    });
  });

  group('toGeminiSchema', () {
    test('turns a [T, "null"] union into T plus nullable', () {
      // Act
      final converted = toGeminiSchema(<String, Object?>{
        'type': <Object?>['null', 'string'],
      });

      // Assert
      expect(
        converted,
        equals(<String, Object?>{'type': 'string', 'nullable': true}),
      );
    });

    test('keeps a single-element type list as its one type', () {
      // Act
      final converted = toGeminiSchema(<String, Object?>{
        'type': <Object?>['string'],
      });

      // Assert
      expect(converted, equals(<String, Object?>{'type': 'string'}));
    });

    test('leaves a multi-type union it cannot express untouched', () {
      // Act
      final converted = toGeminiSchema(<String, Object?>{
        'type': <Object?>['string', 'number'],
      });

      // Assert
      expect(
        converted,
        equals(<String, Object?>{
          'type': <Object?>['string', 'number'],
        }),
      );
    });

    test('converts properties and items recursively', () {
      // Act
      final converted = toGeminiSchema(_schema);

      // Assert
      expect(
        converted,
        equals(<String, Object?>{
          'type': 'object',
          'required': <Object?>['dishes'],
          'properties': <String, Object?>{
            'dishes': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'id': <String, Object?>{'type': 'string'},
                  'net_carbs': <String, Object?>{
                    'type': 'number',
                    'nullable': true,
                  },
                },
              },
            },
          },
        }),
      );
    });

    test('copies a non-object property value as-is', () {
      // Act
      final converted = toGeminiSchema(<String, Object?>{
        'properties': <String, Object?>{'odd': true},
      });

      // Assert
      expect(
        converted,
        equals(<String, Object?>{
          'properties': <String, Object?>{'odd': true},
        }),
      );
    });

    test('never mutates its input and shares no list with it', () {
      // Arrange
      final input = <String, Object?>{
        'enum': <Object?>['a', 'b'],
        'additionalProperties': false,
        'extra': <String, Object?>{
          'nested': <Object?>[1],
        },
      };
      final before = jsonEncode(input);

      // Act
      final converted = toGeminiSchema(input);
      (converted['enum']! as List<Object?>).add('c');
      ((converted['extra']! as Map<String, Object?>)['nested']!
              as List<Object?>)
          .add(2);

      // Assert
      expect(jsonEncode(input), before);
    });
  });
}
