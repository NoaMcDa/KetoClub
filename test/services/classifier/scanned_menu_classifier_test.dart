import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
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

/// A scan-sourced menu with no dishes, for the result value tests.
Menu _menu(String id) => Menu(
  venueRef: VenueRef(source: MenuSource.scan, platformId: id),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[],
);

/// An empty analysis, for the result value tests.
MenuAnalysed _analysis() => MenuAnalysed(
  dishes: const <AnalysedDish>[],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'm'),
  analysedAt: DateTime.utc(2026),
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

  group('ScannedMenuRead', () {
    test('== compares the menu and the analysis', () {
      final a = ScannedMenuRead(menu: _menu('a'), analysis: _analysis());
      final b = ScannedMenuRead(menu: _menu('a'), analysis: _analysis());
      final c = ScannedMenuRead(menu: _menu('c'), analysis: _analysis());

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString names the scan reference', () {
      final read = ScannedMenuRead(menu: _menu('a'), analysis: _analysis());

      expect(read.toString(), contains('scan/a'));
    });
  });

  group('ScannedMenuFailed', () {
    test('== compares the reason', () {
      const a = ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline);
      const b = ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline);
      const c = ScannedMenuFailed(reason: MenuAnalysisFailureReason.timeout);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString names the reason', () {
      const failed = ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.rateLimited,
      );

      expect(failed.toString(), contains('rateLimited'));
    });
  });
}
