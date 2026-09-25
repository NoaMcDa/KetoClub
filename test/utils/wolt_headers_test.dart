import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/wolt_headers.dart';

/// A canonical lowercase version 4 UUID.
final RegExp _uuid4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  group('woltWebHeaders', () {
    test('woltWebHeaders returns the full wolt.com header set', () {
      // Act
      final headers = woltWebHeaders(language: 'he', webClientId: 'client');

      // Assert
      expect(
        headers,
        equals(<String, String>{
          'Accept': 'application/json',
          'platform': 'Web',
          'client-version': woltClientVersion,
          'clientversionnumber': woltClientVersion,
          'app-language': 'he',
          'x-wolt-web-clientid': 'client',
          'w-wolt-session-id': woltSessionIdNoConsent,
          'User-Agent': browserUserAgent,
        }),
      );
    });

    test('woltWebHeaders omits the User-Agent when asked to', () {
      // Act
      final headers = woltWebHeaders(
        language: woltDefaultAppLanguage,
        webClientId: 'client',
        includeUserAgent: false,
      );

      // Assert
      expect(headers.containsKey('User-Agent'), isFalse);
      expect(headers['app-language'], equals('en'));
    });
  });

  group('woltWebClientId', () {
    test('woltWebClientId returns a version 4 UUID', () {
      // Act
      final id = woltWebClientId(Random(42));

      // Assert
      expect(id, matches(_uuid4));
    });

    test('woltWebClientId is deterministic for a seeded source', () {
      // Act
      final first = woltWebClientId(Random(7));
      final second = woltWebClientId(Random(7));

      // Assert
      expect(first, equals(second));
    });
  });
}
