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

    test('the splash draws the steak, the egg and the lettuce in the loader '
        'tokens of both themes (issue #450)', () {
      expect(index, contains('kc-steak'));
      expect(index, contains('kc-egg'));
      expect(index, contains('kc-lettuce'));
      for (final token in [
        AppTokens.lightMeat,
        AppTokens.lightYolk,
        AppTokens.lightLeaf,
        AppTokens.lightVein,
        AppTokens.darkMeat,
        AppTokens.darkYolk,
        AppTokens.darkLeaf,
        AppTokens.darkVein,
      ]) {
        expect(index, contains(_hex(token)), reason: _hex(token));
      }
    });

    test('the splash orbits, and holds still under reduced motion '
        '(issue #450)', () {
      expect(index, contains('@keyframes kc-spin'));
      expect(index, contains('prefers-reduced-motion: reduce'));
      final reduced = index.substring(
        index.indexOf('prefers-reduced-motion: reduce'),
      );
      expect(reduced, contains('animation: none'));
    });

    test('the splash makes no request of its own and announces itself '
        'once (issue #450)', () {
      final splash = index.substring(
        index.indexOf('<div id="splash"'),
        index.indexOf('<div class="kc-name">'),
      );
      expect(splash, isNot(contains('<img')));
      expect(splash, isNot(contains('href=')));
      expect(splash, isNot(contains('src=')));
      expect(index, isNot(contains('url(')));
      expect(index, contains('aria-label="Loading KetoClub"'));
      expect(index, contains('class="kc-stage" aria-hidden="true"'));
    });

    test('the splash is removed on the first frame', () {
      expect(index, contains('flutter-first-frame'));
      expect(index, contains('splash.remove()'));
    });
  });
}
