// The shared QrScanner contract (architecture.md §6.6; issue #182).
//
// Every implementation of QrScanner, including the fake in test/fakes/,
// is run through this suite from its own test file. It asserts only what
// the interface promises for a scanner with nothing to read: scan never
// throws and resolves to null.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';

/// Asserts the [QrScanner] contract against what [build] returns.
void runQrScannerContract(String name, QrScanner Function() build) {
  group(name, () {
    test('scan never throws and resolves to null with nothing to read', () {
      final scanner = build();
      late final Future<String?> future;
      expect(() => future = scanner.scan(), returnsNormally);
      return expectLater(future, completion(isNull));
    });

    test('isAvailable is a plain answer that does not throw', () {
      final scanner = build();
      expect(() => scanner.isAvailable, returnsNormally);
    });
  });
}
