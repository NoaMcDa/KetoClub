import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/route_title.dart';

void main() {
  // These run under plain `flutter test`, so no BANTO_MODE define is set:
  // they pin that a build without the flag is KetoClub unchanged.
  group('BantoMode without the define', () {
    test('is off', () {
      expect(BantoMode.enabled, isFalse);
    });

    test('displays the KetoClub name', () {
      expect(BantoMode.appName, 'KetoClub');
    });

    test('agrees with the product constant', () {
      expect(BantoMode.appName, appName);
    });
  });

  group('documentTitle without the define', () {
    test('is unchanged: page, middle dot, KetoClub', () {
      expect(documentTitle('Hamosad'), 'Hamosad · KetoClub');
      expect(documentTitle('  Saved '), 'Saved · KetoClub');
    });

    test('is the bare name without a page', () {
      expect(documentTitle(null), 'KetoClub');
      expect(documentTitle(''), 'KetoClub');
    });

    test('still takes an explicit app name', () {
      expect(documentTitle('Hamosad', app: 'Banto'), 'Hamosad · Banto');
    });
  });
}
