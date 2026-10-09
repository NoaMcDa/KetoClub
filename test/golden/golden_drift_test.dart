/// The golden parity corpus's drift check (architecture.md D25; issue
/// #320).
///
/// Rebuilds every golden from the real Dart code
/// (`tool/golden/golden_export.dart`) and asserts each equals, byte for
/// byte, the file committed under `backend/tests/fixtures/golden/` — the
/// files the Python port replays in `backend/tests/test_golden_*.py`. A
/// failure here means Dart behaviour moved and the Python port must move
/// with it: regenerate with
///
/// ```bash
/// flutter test --dart-define=UPDATE_GOLDEN=true \
///   test/golden/golden_drift_test.dart
/// ```
///
/// which rewrites the files (and still passes), then make the Python
/// replay green again.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/golden/golden_export.dart';

/// Whether this run rewrites the golden files instead of checking them.
const bool _update = bool.fromEnvironment('UPDATE_GOLDEN');

void main() {
  late Map<String, Object?> goldens;

  setUpAll(() async {
    goldens = await buildGoldens();
    if (_update) {
      Directory(goldenDirectory).createSync(recursive: true);
      for (final name in goldenFileNames) {
        File('$goldenDirectory/$name')
            .writeAsStringSync(encodeGolden(goldens[name]));
      }
    }
  });

  group('golden parity corpus', () {
    test('builds exactly the files it names', () {
      // Assert
      expect(goldens.keys.toList(), goldenFileNames);
    });

    test('the golden directory holds no file the corpus does not build', () {
      // Act
      final onDisk = <String>[
        for (final entity in Directory(goldenDirectory).listSync())
          if (entity is File && entity.path.endsWith('.json'))
            entity.uri.pathSegments.last,
      ]..sort();

      // Assert
      expect(onDisk, <String>[...goldenFileNames]..sort());
    });

    test('is stable: a second build encodes identically', () async {
      // Act
      final again = await buildGoldens();

      // Assert
      for (final name in goldenFileNames) {
        expect(
          encodeGolden(again[name]),
          encodeGolden(goldens[name]),
          reason: name,
        );
      }
    });

    for (final name in goldenFileNames) {
      test('$name matches the committed file', () {
        // Arrange
        final file = File('$goldenDirectory/$name');
        expect(
          file.existsSync(),
          isTrue,
          reason: '$name is missing; run with --dart-define=UPDATE_GOLDEN=true',
        );

        // Act
        final expected = encodeGolden(goldens[name]);

        // Assert: compared as text, so the diff names the first drift.
        expect(
          file.readAsStringSync(),
          expected,
          reason:
              '$name drifted from the Dart code; regenerate with '
              '--dart-define=UPDATE_GOLDEN=true and update the Python port',
        );
      });
    }
  });
}
