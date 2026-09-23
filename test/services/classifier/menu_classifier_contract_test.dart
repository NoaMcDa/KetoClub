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

    test('onEngineStarted takes no part in equality, hashCode or toString '
        '— it observes a call, it does not steer it (issue #65)', () {
      // Arrange
      final heard = <ClassifyingEngine>[];
      final withListener = ClassificationOptions(
        estimationConsentGiven: true,
        onEngineStarted: heard.add,
      );
      const withoutListener = ClassificationOptions(
        estimationConsentGiven: true,
      );

      // Act
      withListener.onEngineStarted?.call(ClassifyingEngine.rules);

      // Assert
      expect(withListener, equals(withoutListener));
      expect(withListener.hashCode, equals(withoutListener.hashCode));
      expect(withListener.toString(), equals(withoutListener.toString()));
      expect(withoutListener.onEngineStarted, isNull);
      expect(heard, equals([ClassifyingEngine.rules]));
    });
  });
}
