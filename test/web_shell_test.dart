import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/theme/app_tokens.dart';

/// `#RRGGBB` for [color], the way `web/` files write it.
String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
        .toUpperCase();

void main() {
  group('web shell (issue #226)', () {
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final index = File('web/index.html').readAsStringSync();

    test('the manifest colours are the light background token', () {
      expect(manifest['background_color'], _hex(AppTokens.lightBg));
      expect(manifest['theme_color'], _hex(AppTokens.lightBg));
    });

    test('the manifest does not lock the orientation', () {
      expect(manifest.containsKey('orientation'), isFalse);
    });

    test('the splash uses the background tokens and names the app', () {
      expect(index, contains('id="splash"'));
      expect(index, contains('>KetoClub</div>'));
      expect(index, contains('background: ${_hex(AppTokens.lightBg)}'));
      expect(index, contains('background: ${_hex(AppTokens.darkBg)}'));
    });

    test('the splash is removed on the first frame', () {
      expect(index, contains('flutter-first-frame'));
      expect(index, contains('splash.remove()'));
    });
  });
}
