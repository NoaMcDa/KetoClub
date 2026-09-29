import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';

import 'qr_scanner_contract.dart';

void main() {
  runQrScannerContract('NoQrScanner', NoQrScanner.new);

  group('NoQrScanner', () {
    test('is unavailable, so the Scan tab hides its QR action', () {
      expect(const NoQrScanner().isAvailable, isFalse);
    });
  });
}
