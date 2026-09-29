// The shared ScannedMenuClassifier contract (architecture.md §6.2, §18.1,
// D15; issue #89).
//
// Every implementation of ScannedMenuClassifier, including the fake in
// test/fakes/, is run through this suite from its own test file. Like the
// MenuClassifier contract it is silent on verdicts and on whether a given
// scan is read or fails: a placeholder that answers notConfigured and a
// vision engine that reads every page are both correct. Only the shape of
// a result, and the provenance of a read menu, are asserted.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/utils/constants.dart';

/// A small page whose bytes differ by [seed], so pages are distinct.
ScannedPage _page(int seed, {String mimeType = ScannedPage.jpeg}) =>
    ScannedPage(
      mimeType: mimeType,
      bytes: Uint8List.fromList(<int>[0xff, 0xd8, seed, 0xff, 0xd9]),
    );

/// A scan of [count] pages, the last one a PDF when [count] is above 1.
ScannedMenu _scanOf(int count) => ScannedMenu(
  pages: <ScannedPage>[
    for (var i = 0; i < count; i++)
      _page(
        i,
        mimeType: i == count - 1 && count > 1
            ? ScannedPage.pdf
            : ScannedPage.jpeg,
      ),
  ],
);

/// Options that differ from the defaults in every field that shapes a
/// verdict, so a recorded snapshot cannot match by accident.
const ClassificationOptions _steered = ClassificationOptions(
  estimationConsentGiven: true,
  netCarbLimitGrams: 9,
  dietaryConstraints: <String>[dairyFreePromptFragment],
);

/// Asserts the [ScannedMenuClassifier] contract against what [build]
/// returns.
///
/// When [recordedOptions] is given it reads back, from the instance
/// [build] made, the options of every call so far; the suite then checks
/// that each call recorded exactly the options it was made with. An
/// implementation with nothing to record (the shipped placeholder) passes
/// null.
void runScannedMenuClassifierContract<T extends ScannedMenuClassifier>(
  String name,
  T Function() build, {
  List<ClassificationOptions> Function(T classifier)? recordedOptions,
}) {
  group(name, () {
    for (final count in <int>[0, 1, maxScanPages]) {
      test('classify never throws and resolves for $count pages', () async {
        final classifier = build();
        late final Future<ScannedMenuResult> future;
        expect(
          () => future = classifier.classify(
            _scanOf(count),
            options: const ClassificationOptions(),
          ),
          returnsNormally,
        );
        await expectLater(future, completion(isA<ScannedMenuResult>()));
      });

      test('a read of $count pages is a scan-sourced menu whose analysis '
          'names only its dishes', () async {
        final result = await build().classify(
          _scanOf(count),
          options: const ClassificationOptions(),
        );
        if (result is! ScannedMenuRead) return;
        expect(result.menu.venueRef.source, equals(MenuSource.scan));
        final ids = {for (final dish in result.menu.allDishes) dish.id};
        for (final dish in result.analysis.dishes) {
          expect(ids, contains(dish.dishId));
          expect(dish.why.trim(), isNotEmpty);
        }
      });
    }

    test('a read records the verdict-shaping options it was given', () async {
      final result = await build().classify(_scanOf(1), options: _steered);
      if (result is! ScannedMenuRead) return;
      expect(result.analysis.options, equals(_steered.snapshot));
    });

    if (recordedOptions != null) {
      test('records the options of every call, in order', () async {
        final classifier = build();

        await classifier.classify(
          _scanOf(1),
          options: const ClassificationOptions(),
        );
        await classifier.classify(_scanOf(2), options: _steered);

        expect(
          recordedOptions(classifier),
          equals(<ClassificationOptions>[
            const ClassificationOptions(),
            _steered,
          ]),
        );
      });
    }
  });
}
