import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/qr_payload_router.dart';

/// The [QrTarget] a payload that opens [platformId] on [source] answers.
QrVenue _venue(MenuSource source, String platformId) =>
    QrVenue(VenueRef(source: source, platformId: platformId));

const QrTarget _tabit = QrUnsupportedSource('Tabit');
const QrTarget _photograph = QrPhotographInstead();

void main() {
  // One row per kind of code a table carries in Israel
  // (docs/menu_sources_research.md §3.6), then the shapes that are not
  // a menu link at all.
  final table = <String, (String, QrTarget)>{
    // Delivery platforms: the existing adapters.
    'a Wolt venue page': (
      'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
      _venue(MenuSource.wolt, 'vitrina-lilinblum'),
    ),
    'a Wolt venue page with no scheme': (
      'wolt.com/he/isr/tel-aviv/restaurant/hamosad-food?ref=qr',
      _venue(MenuSource.wolt, 'hamosad-food'),
    ),
    'a 10bis venue page': (
      'https://www.10bis.co.il/next/restaurants/menu/delivery/123456/cafe',
      _venue(MenuSource.tenbis, '123456'),
    ),
    // A PDF is a website URL: the website adapter hands it to vision.
    'a PDF on static.rest.co.il': (
      'https://static.rest.co.il/12345678/29092026/menu.pdf',
      _venue(
        MenuSource.website,
        'https://static.rest.co.il/12345678/29092026/menu.pdf',
      ),
    ),
    'a PDF on any other host': (
      'https://cafe.example.co.il/files/menu.pdf',
      _venue(MenuSource.website, 'https://cafe.example.co.il/files/menu.pdf'),
    ),
    'a Wix site menu page': (
      'https://someone.wixsite.com/resto/menu',
      _venue(MenuSource.website, 'https://someone.wixsite.com/resto/menu'),
    ),
    "a restaurant's own site": (
      'https://www.cafe-noa.co.il/',
      _venue(MenuSource.website, 'https://www.cafe-noa.co.il'),
    ),
    'a tafryt page': (
      'https://menu.tafryt.co.il/greg',
      _venue(MenuSource.website, 'https://menu.tafryt.co.il/greg'),
    ),
    'a C-MENU page': (
      'https://cmenu.co.il/resto/table-4',
      _venue(MenuSource.website, 'https://cmenu.co.il/resto/table-4'),
    ),
    'an OurMenu page': (
      'https://ourmenu.co.il/resto',
      _venue(MenuSource.website, 'https://ourmenu.co.il/resto'),
    ),
    'a qrmenu.co.il page': (
      'https://qrmenu.co.il/abc123',
      _venue(MenuSource.website, 'https://qrmenu.co.il/abc123'),
    ),
    'a page with surrounding whitespace': (
      '  https://wolt.com/en/isr/tel-aviv/restaurant/hamosad-food\n',
      _venue(MenuSource.wolt, 'hamosad-food'),
    ),
    'a lookalike of a Tabit host, which is just a website': (
      'https://tabit.cloud.example.com/menu',
      _venue(MenuSource.website, 'https://tabit.cloud.example.com/menu'),
    ),
    'a lookalike of Instagram, which is just a website': (
      'https://notinstagram.com/resto',
      _venue(MenuSource.website, 'https://notinstagram.com/resto'),
    ),

    // Tabit: not supported until its adapter exists.
    'a Tabit ordering page': (
      'https://tabitisrael.co.il/tabit-order?siteName=cafe-noa',
      _tabit,
    ),
    'a Tabit ordering page in capitals': (
      'HTTPS://TABITISRAEL.CO.IL/TABIT-ORDER?siteName=cafe-noa',
      _tabit,
    ),
    'a Tabit cloud page': ('https://tabit.cloud/menu/abc', _tabit),
    'a Tabit Pay page': ('https://pay.tabit.cloud/bill/abc', _tabit),
    'the US Tabit mirror': (
      'https://tabit.us/tabit-order?orgName=cafe-noa',
      _tabit,
    ),
    'a tabit-order path on another host': (
      'https://orders.example.co.il/tabit-order/abc',
      _tabit,
    ),

    // Social and link-in-bio pages, and anything that is not a link:
    // photograph the menu instead.
    'an Instagram profile': (
      'https://www.instagram.com/cafe.noa/',
      _photograph,
    ),
    'an Instagram profile with no www': (
      'https://instagram.com/cafe.noa',
      _photograph,
    ),
    'an Instagram redirect': (
      'https://l.instagram.com/?u=https%3A%2F%2Fcafe.co.il',
      _photograph,
    ),
    'an instagr.am short link': ('https://instagr.am/p/abc', _photograph),
    'a Linktree page': ('https://linktr.ee/cafe.noa', _photograph),
    'plain text': ('Table 12', _photograph),
    'a sentence that contains a domain': (
      'see cafe.co.il/menu for the menu',
      _photograph,
    ),
    'an empty payload': ('', _photograph),
    'a blank payload': ('   \n ', _photograph),
    'a bare Wolt-style slug': ('vitrina-lilinblum', _photograph),
    'a bare number': ('123456', _photograph),
    'a Wi-Fi code': ('WIFI:S:cafe;T:WPA;P:secret;;', _photograph),
    'a mailto link': ('mailto:hello@cafe.co.il', _photograph),
    'a phone link': ('tel:+972501234567', _photograph),
    'a Wolt page that names no venue': ('https://wolt.com/en/isr', _photograph),
    'a 10bis page with no restaurant id': (
      'https://www.10bis.co.il/next/en/home',
      _photograph,
    ),
    'a non-http URL': ('ftp://cafe.co.il/menu', _photograph),
    'a URL with a host that has no dot': (
      'http://localhost:8080/menu',
      _photograph,
    ),
    'a URL with user info': ('https://user:pw@cafe.co.il/menu', _photograph),
  };

  group('QrPayloadRouter.classify', () {
    for (final MapEntry(key: name, value: (payload, expected))
        in table.entries) {
      test(name, () {
        expect(QrPayloadRouter.classify(payload), equals(expected));
      });
    }

    test('never throws on odd input', () {
      for (final payload in <String>[
        '%',
        'http://',
        'https://[::1',
        '://',
        '\u0000',
        'https://cafe.co.il/%zz',
        'א' * 500,
      ]) {
        expect(
          () => QrPayloadRouter.classify(payload),
          returnsNormally,
          reason: payload,
        );
      }
    });
  });

  group('QrTarget equality', () {
    test('two targets of one kind and value are equal', () {
      expect(
        _venue(MenuSource.wolt, 'a-b'),
        equals(_venue(MenuSource.wolt, 'a-b')),
      );
      expect(
        _venue(MenuSource.wolt, 'a-b').hashCode,
        _venue(MenuSource.wolt, 'a-b').hashCode,
      );
      expect(const QrUnsupportedSource('Tabit').hashCode, _tabit.hashCode);
      expect(const QrPhotographInstead().hashCode, _photograph.hashCode);
    });

    test('targets that differ are not equal', () {
      expect(
        _venue(MenuSource.wolt, 'a-b'),
        isNot(_venue(MenuSource.wolt, 'c-d')),
      );
      expect(_tabit, isNot(const QrUnsupportedSource('Ontopo')));
      expect(_tabit, isNot(_photograph));
    });
  });
}
