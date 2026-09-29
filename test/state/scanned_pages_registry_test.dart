import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';

/// A scan-sourced reference with [id].
VenueRef _ref(String id) => VenueRef(source: MenuSource.scan, platformId: id);

/// A one-page scan whose bytes differ by [seed].
ScannedMenu _scan(int seed) => ScannedMenu(
  pages: <ScannedPage>[
    ScannedPage(
      mimeType: ScannedPage.jpeg,
      bytes: Uint8List.fromList(<int>[seed]),
    ),
  ],
);

void main() {
  group('ScannedPagesRegistry', () {
    test('holds nothing to begin with', () {
      // Assert
      expect(ScannedPagesRegistry().get(_ref('a')), isNull);
    });

    test('returns the pages put for a reference', () {
      // Arrange
      final registry = ScannedPagesRegistry()..put(_ref('a'), _scan(1));

      // Assert
      expect(registry.get(_ref('a')), _scan(1));
      expect(registry.get(_ref('b')), isNull);
    });

    test('a second put for the same reference replaces the first', () {
      // Arrange
      final registry = ScannedPagesRegistry()
        ..put(_ref('a'), _scan(1))
        ..put(_ref('a'), _scan(2));

      // Assert
      expect(registry.get(_ref('a')), _scan(2));
    });

    test('remove forgets the pages, and tolerates an unknown ref', () {
      // Arrange and act
      final registry = ScannedPagesRegistry()
        ..put(_ref('a'), _scan(1))
        ..remove(_ref('a'))
        ..remove(_ref('never-put'));

      // Assert
      expect(registry.get(_ref('a')), isNull);
    });

    test('evicts the oldest scan beyond its capacity', () {
      // Arrange: a then b, then a again.
      final registry = ScannedPagesRegistry(capacity: 2)
        ..put(_ref('a'), _scan(1))
        ..put(_ref('b'), _scan(2))
        // Re-putting a makes b the oldest.
        ..put(_ref('a'), _scan(3))
        // Act: one more than the capacity.
        ..put(_ref('c'), _scan(4));

      // Assert
      expect(registry.get(_ref('b')), isNull);
      expect(registry.get(_ref('a')), _scan(3));
      expect(registry.get(_ref('c')), _scan(4));
    });

    test('defaults to a small capacity', () {
      // Assert
      expect(
        ScannedPagesRegistry().capacity,
        ScannedPagesRegistry.defaultCapacity,
      );
      expect(ScannedPagesRegistry.defaultCapacity, greaterThan(0));
    });
  });
}
