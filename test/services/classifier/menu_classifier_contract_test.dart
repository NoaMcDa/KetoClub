import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/utils/constants.dart';

import '../../fakes/fake_menu_classifier.dart';
import 'menu_classifier_contract.dart';

void main() {
  runMenuClassifierContract('FakeMenuClassifier', FakeMenuClassifier.new);

  group('ClassificationOptions value semantics', () {
    test('equal fields make two instances equal', () {
      const a = ClassificationOptions(
        estimationConsentGiven: true,
        dietaryConstraints: ['seed-oil free'],
      );
      const b = ClassificationOptions(
        estimationConsentGiven: true,
        dietaryConstraints: ['seed-oil free'],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('ClassificationOptions'));
    });

    test('a differing consent flag makes two instances unequal', () {
      const a = ClassificationOptions();
      const b = ClassificationOptions(estimationConsentGiven: true);
      expect(a, isNot(equals(b)));
    });

    test('differing-length constraint lists make two instances unequal', () {
      const a = ClassificationOptions(dietaryConstraints: ['dairy-free']);
      const b = ClassificationOptions(
        dietaryConstraints: ['dairy-free', 'carnivore'],
      );
      expect(a, isNot(equals(b)));
    });

    test('same-length but differing constraint lists make two instances '
        'unequal', () {
      const a = ClassificationOptions(dietaryConstraints: ['dairy-free']);
      const b = ClassificationOptions(dietaryConstraints: ['carnivore']);
      expect(a, isNot(equals(b)));
    });

    test('the net-carb limit defaults to 6 g', () {
      expect(
        const ClassificationOptions().netCarbLimitGrams,
        equals(defaultNetCarbLimitGrams),
      );
    });

    test('a differing net-carb limit makes two instances unequal', () {
      const a = ClassificationOptions();
      const b = ClassificationOptions(netCarbLimitGrams: 9);
      expect(a, isNot(equals(b)));
      expect(b.toString(), contains('9g'));
    });
  });

  group('ClassificationOptions.snapshot and matches (issue #57)', () {
    test('snapshot records the limit and the constraints, not consent', () {
      const options = ClassificationOptions(
        estimationConsentGiven: true,
        netCarbLimitGrams: 8,
        dietaryConstraints: ['carnivore'],
      );
      expect(
        options.snapshot,
        equals(
          const AnalysisOptionsSnapshot(
            netCarbLimitGrams: 8,
            dietaryConstraints: ['carnivore'],
          ),
        ),
      );
    });

    test('matches its own snapshot whatever the consent flag', () {
      const withConsent = ClassificationOptions(
        estimationConsentGiven: true,
        netCarbLimitGrams: 8,
      );
      const withoutConsent = ClassificationOptions(netCarbLimitGrams: 8);
      expect(withConsent.matches(withoutConsent.snapshot), isTrue);
    });

    test('does not match a snapshot with a different limit', () {
      const options = ClassificationOptions(netCarbLimitGrams: 8);
      expect(
        options.matches(const AnalysisOptionsSnapshot(netCarbLimitGrams: 6)),
        isFalse,
      );
    });

    test('does not match a snapshot with different constraints', () {
      const options = ClassificationOptions(dietaryConstraints: ['dairy-free']);
      expect(
        options.matches(
          const AnalysisOptionsSnapshot(
            netCarbLimitGrams: defaultNetCarbLimitGrams,
          ),
        ),
        isFalse,
      );
    });

    test('reads a missing snapshot as the defaults, which every analysis '
        'cached before issue #57 was made under', () {
      expect(const ClassificationOptions().matches(null), isTrue);
      expect(
        const ClassificationOptions(netCarbLimitGrams: 7).matches(null),
        isFalse,
      );
    });
  });
}
