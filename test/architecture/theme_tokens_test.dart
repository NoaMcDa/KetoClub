// Architecture test: no colour literal outside the theme layer
// (architecture.md §5, the "theme/ layer" note; issue #9).
//
// Written in the same style as import_rules_test.dart: walk lib/, apply a
// regex per file, and fail with every violation named in one `expect`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lib-relative path prefixes exempt from the colour-literal ban.
///
/// `theme/` is where every colour literal is meant to live. `l10n/generated/`
/// is `flutter gen-l10n` output, excluded from every other gate in this repo
/// for the same reason (import_rules_test.dart, the analyzer, the coverage
/// gate) — it is not authored code.
const _exemptPrefixes = <String>['theme/', 'l10n/generated/'];

/// One regex per banned construct, paired with the fix to name in the
/// failure message.
const _bannedPatterns = <String, String>{
  r'Color\(0x':
      'use a named constant from lib/theme/app_tokens.dart instead '
      'of Color(0x...)',
  r'Color\.fromARGB':
      'use a named constant from lib/theme/app_tokens.dart '
      'instead of Color.fromARGB(...)',
  r'Color\.fromRGBO':
      'use a named constant from lib/theme/app_tokens.dart '
      'instead of Color.fromRGBO(...)',
  // The negative lookbehind keeps this off `VerdictColors.` (and any other
  // `...Colors.` identifier) — only the framework's own `Colors` palette,
  // never preceded by a letter, is banned.
  r'(?<![A-Za-z])Colors\.':
      'read the colour from VerdictColors.of(context) or '
      'Theme.of(context).colorScheme instead of the Colors palette',
};

/// Whether [relativePath] (lib-relative, `/`-separated) is exempt from the
/// colour-literal ban.
bool _isExempt(String relativePath) =>
    _exemptPrefixes.any(relativePath.startsWith);

String _toLibRelative(String path) {
  final normalised = path.replaceAll(r'\', '/');
  final idx = normalised.indexOf('lib/');
  return normalised.substring(idx + 'lib/'.length);
}

void main() {
  test('no colour literal appears outside lib/theme/', () {
    final lib = Directory('lib');
    final dartFiles =
        lib
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final violations = <String>[];
    for (final file in dartFiles) {
      final relative = _toLibRelative(file.path);
      if (_isExempt(relative)) continue;
      final source = file.readAsStringSync();
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final entry in _bannedPatterns.entries) {
          if (RegExp(entry.key).hasMatch(lines[i])) {
            violations.add(
              'lib/$relative:${i + 1} matches ${entry.key} — ${entry.value}',
            );
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Colour literals found outside lib/theme/ '
          '(architecture.md §5, issue #9):\n${violations.join('\n')}',
    );
  });
}
