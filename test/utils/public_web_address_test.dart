import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/public_web_address.dart';

void main() {
  group('isPublicHost (issue #181)', () {
    for (final host in [
      'cafe-noir.co.il',
      'www.cafe.example',
      'cafe.example.',
      '93.184.215.14',
      '8.8.8.8',
      '2a00:1450:4001:80b::200e',
      '::ffff:8.8.8.8',
    ]) {
      test('accepts $host', () => expect(isPublicHost(host), isTrue));
    }

    for (final host in [
      '',
      '.',
      'localhost',
      'LOCALHOST.',
      'app.localhost',
      'printer.local',
      'router',
      '0.0.0.0',
      '10.1.2.3',
      '100.64.0.1',
      '127.0.0.1',
      '169.254.169.254',
      '172.16.0.1',
      '172.31.255.255',
      '192.0.2.1',
      '192.168.0.1',
      '198.18.0.1',
      '224.0.0.1',
      '255.255.255.255',
      '127.1',
      '2130706433',
      '0x7f.0.0.1',
      '010.0.0.1',
      '256.1.1.1',
      '1.2.3.4.5',
      '::',
      '::1',
      'fc00::1',
      'fd00::1',
      'fe80::1',
      'ff02::1',
      '2001:db8::1',
      '2001::1',
      '2002::1',
      '::ffff:127.0.0.1',
      '::ffff:10.0.0.1',
      'fe80::1%25eth0',
      'not:an:address',
    ]) {
      test('refuses "$host"', () => expect(isPublicHost(host), isFalse));
    }
  });

  group('isPublicWebUrl (issue #181)', () {
    for (final url in [
      'https://cafe.example/',
      'http://cafe.example/menu?x=1',
      'https://cafe.example:443/',
      'http://cafe.example:80/',
      'http://cafe.example:443/',
      'http://[2a00:1450:4001:80b::200e]/',
    ]) {
      test('accepts $url', () {
        expect(isPublicWebUrl(Uri.parse(url)), isTrue);
      });
    }

    for (final url in [
      'ftp://cafe.example/menu.pdf',
      'file:///etc/passwd',
      'https://cafe.example:8443/',
      'http://cafe.example:8080/',
      'https://user@cafe.example/',
      'https://user:pw@cafe.example/',
      'http://127.0.0.1/',
      'http://[::1]/',
      'http://localhost:80/',
    ]) {
      test('refuses $url', () {
        expect(isPublicWebUrl(Uri.parse(url)), isFalse);
      });
    }
  });
}
