import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';

import 'scanned_menu_classifier_contract.dart';

/// A one-page scan.
ScannedMenu _onePage() => ScannedMenu(
  pages: <ScannedPage>[
    ScannedPage(
      mimeType: ScannedPage.png,
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    ),
  ],
);

void main() {
  runScannedMenuClassifierContract(
    'UnavailableScannedMenuClassifier',
    UnavailableScannedMenuClassifier.new,
  );

  group('UnavailableScannedMenuClassifier', () {
    test('answers notConfigured for any scan', () async {
      // Act
      final result = await const UnavailableScannedMenuClassifier().classify(
        _onePage(),
        options: const ClassificationOptions(),
      );

      // Assert
      expect(
        result,
        equals(
          const ScannedMenuFailed(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
        ),
      );
    });

    test('announces no engine: it never starts one', () async {
      // Arrange
      final heard = <ClassifyingEngine>[];

      // Act
      await const UnavailableScannedMenuClassifier().classify(
        _onePage(),
        options: ClassificationOptions(onEngineStarted: heard.add),
      );

      // Assert
      expect(heard, isEmpty);
    });
  });
}
