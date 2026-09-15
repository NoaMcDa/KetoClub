// Architecture test: no hardcoded user-facing string in lib/ (architecture.md
// §12; issue #8's acceptance criteria).
//
// Written in the same style as import_rules_test.dart and
// theme_tokens_test.dart: walk lib/, apply a regex per file, and fail with
// every violation named in one `expect`. A `Text('literal')` or
// `Text("literal")` is exactly the shape a string that skipped
// `AppLocalizations` takes, since every legitimate call passes an
// `AppLocalizations` getter or a non-literal expression instead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lib-relative path prefixes exempt from the ban.
///
/// `l10n/generated/` is `flutter gen-l10n` output, excluded from every other
/// gate in this repo for the same reason (import_rules_test.dart, the
/// analyzer, the coverage gate) — it is not authored code, and does not call
/// `Text` at all.
const _exemptPrefixes = <String>['l10n/generated/'];

/// A `Text(` call opening directly on a single- or double-quoted string
/// literal. Deliberately does not try to also catch `Text.rich(` or a
/// literal buried inside a larger expression — the acceptance criterion is
/// this one common shape, and a narrower net that never false-positives on
/// legitimate code (an identifier, a getter, string interpolation used only
/// for a non-literal) is worth more than a broader one that needs constant
/// exceptions.
final _literalText = RegExp(r'''Text\(\s*['"]''');

/// Whether [relativePath] (lib-relative, `/`-separated) is exempt.
bool _isExempt(String relativePath) =>
    _exemptPrefixes.any(relativePath.startsWith);

void main() {
  test('no lib/ file passes a string literal straight to Text()', () {
    final lib = Directory('lib');
    final violations = <String>[];

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceAll(r'\', '/').split('lib/').last;
      if (_isExempt(relative)) continue;

      final source = entity.readAsStringSync();
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (_literalText.hasMatch(lines[i])) {
          violations.add('lib/$relative:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Every user-facing string must come from AppLocalizations '
          '(architecture.md §12). Add an ARB key instead:\n'
          '${violations.join('\n')}',
    );
  });
}
