import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/scanned_menu.dart';

/// A page of [mimeType] holding [bytes].
ScannedPage _page(List<int> bytes, {String mimeType = ScannedPage.jpeg}) =>
    ScannedPage(mimeType: mimeType, bytes: Uint8List.fromList(bytes));

void main() {
  group('ScannedPage', () {
    test('equal mime type and bytes make two pages equal', () {
      final a = _page(<int>[1, 2, 3]);
      final b = _page(<int>[1, 2, 3]);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.contentHash, equals(b.contentHash));
    });

    test('a differing mime type makes two pages unequal', () {
      final a = _page(<int>[1, 2, 3]);
      final b = _page(<int>[1, 2, 3], mimeType: ScannedPage.png);

      expect(a, isNot(equals(b)));
    });

    test('a differing length makes two pages unequal', () {
      expect(_page(<int>[1, 2]), isNot(equals(_page(<int>[1, 2, 3]))));
    });

    test('same-length but differing bytes make two pages unequal', () {
      final a = _page(<int>[1, 2, 3]);
      final b = _page(<int>[1, 2, 4]);

      expect(a, isNot(equals(b)));
      expect(a.contentHash, isNot(equals(b.contentHash)));
    });

    test('bytes that collide on the content hash are still unequal', () {
      // [0, 31] and [1, 0] hash alike: (17 * 31 + 0) * 31 + 31 equals
      // (17 * 31 + 1) * 31 + 0. Equality must not rest on the hash alone.
      final a = _page(<int>[0, 31]);
      final b = _page(<int>[1, 0]);

      expect(a.contentHash, equals(b.contentHash));
      expect(a, isNot(equals(b)));
    });

    test('is not equal to another type', () {
      expect(_page(<int>[1]), isNot(equals('page')));
    });

    test('bytes cannot be changed through the page', () {
      final page = _page(<int>[1, 2, 3]);

      expect(() => page.bytes[0] = 9, throwsUnsupportedError);
    });

    test('toString names the type and size, never the bytes', () {
      final page = _page(<int>[101, 102, 103, 104]);

      final text = page.toString();

      expect(text, equals('ScannedPage(image/jpeg, 4 bytes)'));
      expect(text, isNot(contains('101')));
    });

    test('the content hash stays within 30 bits, exact on the web', () {
      final page = _page(List<int>.filled(4096, 0xff));

      expect(page.contentHash, lessThan(1 << 30));
      expect(page.contentHash, greaterThanOrEqualTo(0));
    });

    test('isPdf is true only for application/pdf', () {
      expect(_page(<int>[1], mimeType: ScannedPage.pdf).isPdf, isTrue);
      expect(_page(<int>[1]).isPdf, isFalse);
      expect(_page(<int>[1], mimeType: ScannedPage.webp).isPdf, isFalse);
    });
  });

  group('ScannedMenu', () {
    test('equal pages in the same order make two scans equal', () {
      final a = ScannedMenu(
        pages: [
          _page(<int>[1]),
          _page(<int>[2]),
        ],
      );
      final b = ScannedMenu(
        pages: [
          _page(<int>[1]),
          _page(<int>[2]),
        ],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, equals(a));
    });

    test('the same pages in a different order make two scans unequal', () {
      final a = ScannedMenu(
        pages: [
          _page(<int>[1]),
          _page(<int>[2]),
        ],
      );
      final b = ScannedMenu(
        pages: [
          _page(<int>[2]),
          _page(<int>[1]),
        ],
      );

      expect(a, isNot(equals(b)));
    });

    test('a differing page count makes two scans unequal', () {
      final a = ScannedMenu(
        pages: [
          _page(<int>[1]),
        ],
      );
      final b = ScannedMenu(
        pages: [
          _page(<int>[1]),
          _page(<int>[2]),
        ],
      );

      expect(a, isNot(equals(b)));
      expect(a, isNot(equals('scan')));
    });

    test('pages are unmodifiable', () {
      final scan = ScannedMenu(
        pages: [
          _page(<int>[1]),
        ],
      );

      expect(() => scan.pages.add(_page(<int>[2])), throwsUnsupportedError);
    });

    test('changing the list passed in does not change the scan', () {
      final pages = <ScannedPage>[
        _page(<int>[1]),
      ];
      final scan = ScannedMenu(pages: pages);

      pages.add(_page(<int>[2]));

      expect(scan.pages, hasLength(1));
    });

    test('totalBytes sums every page', () {
      final scan = ScannedMenu(
        pages: [
          _page(<int>[1, 2]),
          _page(<int>[3, 4, 5]),
        ],
      );

      expect(scan.totalBytes, equals(5));
    });

    test('toString names the page count and size, never the bytes', () {
      final scan = ScannedMenu(
        pages: [
          _page(<int>[201, 202]),
        ],
      );

      final text = scan.toString();

      expect(text, equals('ScannedMenu(1 pages, 2 bytes)'));
      expect(text, isNot(contains('201')));
    });
  });
}
