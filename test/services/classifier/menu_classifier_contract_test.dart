import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
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

    test('a differing net-carb limit makes two instances unequal', () {
      const a = ClassificationOptions();
      const b = ClassificationOptions(netCarbLimitGrams: 9);
      expect(a, isNot(equals(b)));
      expect(b.toString(), contains('9g'));
    });
  });

  group('ClassificationOptions.fromSettings (issue #181)', () {
    test('carries consent, the limit and the toggles in fixed order', () {
      // Arrange
      const settings = AppSettings(
        estimationConsentGiven: false,
        netCarbLimitGrams: 9,
        carnivoreOnly: true,
        seedOilFree: true,
      );
      final engines = <ClassifyingEngine>[];

      // Act
      final options = ClassificationOptions.fromSettings(
        settings,
        onEngineStarted: engines.add,
      );
      options.onEngineStarted?.call(ClassifyingEngine.llm);

      // Assert
      expect(options.estimationConsentGiven, isFalse);
      expect(options.netCarbLimitGrams, 9);
      expect(options.dietaryConstraints, [
        seedOilFreePromptFragment,
        carnivoreOnlyPromptFragment,
      ]);
      expect(engines, [ClassifyingEngine.llm]);
      // Two callers building from the same settings ask the same question.
      expect(
        options.matches(ClassificationOptions.fromSettings(settings).snapshot),
        isTrue,
      );
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

  group('ClassificationOptions.restrictionsRequested (D26 W2-0)', () {
    test('defaults to false, and fromSettings leaves it false by '
        'default', () {
      expect(const ClassificationOptions().restrictionsRequested, isFalse);
      expect(
        ClassificationOptions.fromSettings(const AppSettings())
            .restrictionsRequested,
        isFalse,
      );
    });

    test('takes part in equality, hashCode and toString', () {
      const off = ClassificationOptions();
      const on = ClassificationOptions(restrictionsRequested: true);
      expect(on, isNot(equals(off)));
      expect(
        on,
        equals(const ClassificationOptions(restrictionsRequested: true)),
      );
      expect(
        on.hashCode,
        const ClassificationOptions(restrictionsRequested: true).hashCode,
      );
      expect(on.toString(), contains('restrictions: true'));
    });

    test('snapshot records it, and a keto snapshot is unchanged', () {
      expect(
        const ClassificationOptions(restrictionsRequested: true)
            .snapshot
            .restrictionsRequested,
        isTrue,
      );
      expect(const ClassificationOptions().snapshot.toJson().keys, [
        'netCarbLimitGrams',
        'dietaryConstraints',
      ]);
    });

    test('a cached analysis made without it is retired when it turns on, '
        'and the other way round', () {
      const off = ClassificationOptions();
      const on = ClassificationOptions(restrictionsRequested: true);
      expect(on.matches(off.snapshot), isFalse);
      expect(on.matches(null), isFalse);
      expect(off.matches(on.snapshot), isFalse);
      expect(on.matches(on.snapshot), isTrue);
    });
  });

  group('ClassificationOptions.fromSettings restrictionsRequested '
      '(ALG-03, D26 C2)', () {
    AppSettings withProfile(List<RestrictionId> ids) {
      var profile = DietaryProfile.empty;
      for (final id in ids) {
        profile = profile.withEntry(id);
      }
      return const AppSettings().copyWith(profile: profile);
    }

    // (profile, bantoMode, expected)
    const table = <(List<RestrictionId>, bool, bool)>[
      (<RestrictionId>[], false, false),
      (<RestrictionId>[], true, false),
      (<RestrictionId>[RestrictionId.keto], true, false),
      (<RestrictionId>[RestrictionId.sesame], false, false),
      (<RestrictionId>[RestrictionId.sesame], true, true),
      (<RestrictionId>[RestrictionId.keto, RestrictionId.gluten], true, true),
    ];
    for (final (ids, bantoMode, expected) in table) {
      test('is $expected for ${ids.map((id) => id.name).toList()} with '
          'bantoMode $bantoMode', () {
        // Act
        final options = ClassificationOptions.fromSettings(
          withProfile(ids),
          bantoMode: bantoMode,
        );

        // Assert
        expect(options.restrictionsRequested, expected);
      });
    }

    test('a keto-only profile with bantoMode on gives the keto options', () {
      // Act
      final options = ClassificationOptions.fromSettings(
        withProfile(const <RestrictionId>[RestrictionId.keto]),
        bantoMode: true,
      );

      // Assert
      expect(options, ClassificationOptions.fromSettings(const AppSettings()));
    });
  });
}
