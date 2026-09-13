import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';

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
  });
}
