import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';

void main() {
  group('DishVerdict', () {
    test('tryParse returns the verdict whose name matches the wire value', () {
      // Arrange
      const wire = 'modifiable';

      // Act
      final result = DishVerdict.tryParse(wire);

      // Assert
      expect(result, equals(DishVerdict.modifiable));
    });

    test('tryParse returns null for an unknown string', () {
      // Arrange
      const wire = 'unsure';

      // Act
      final result = DishVerdict.tryParse(wire);

      // Assert
      expect(result, isNull);
    });
  });

  group('MenuFilter', () {
    test('tryParse returns the filter whose name matches the wire value', () {
      // Arrange
      const wire = 'greenAndYellow';

      // Act
      final result = MenuFilter.tryParse(wire);

      // Assert
      expect(result, equals(MenuFilter.greenAndYellow));
    });

    test('tryParse returns null for an unknown string', () {
      // Arrange: not one of MenuFilter.values' names.
      const wire = 'purple';

      // Act
      final result = MenuFilter.tryParse(wire);

      // Assert
      expect(result, isNull);
    });

    test('tryParse returns yellowOnly and redOnly — added by issue #29 for '
        "the menu screen's per-verdict counter tiles, additively so an "
        'already-persisted greenAndYellow or all keeps decoding unchanged', () {
      // Act & Assert
      expect(MenuFilter.tryParse('yellowOnly'), MenuFilter.yellowOnly);
      expect(MenuFilter.tryParse('redOnly'), MenuFilter.redOnly);
    });
  });

  group('AnalysedDish', () {
    const modifiableJson = <String, Object?>{
      'dishId': 'd1',
      'name': 'Steak',
      'verdict': 'modifiable',
      'why': 'Comes with fries',
      'modification': 'Ask for a green salad instead of fries',
      'netCarbsEstimate': 8.0,
    };
    const orderAsIsJson = <String, Object?>{
      'dishId': 'd2',
      'name': 'Grilled chicken',
      'verdict': 'orderAsIs',
      'why': 'Plain protein',
      'modification': null,
      'netCarbsEstimate': null,
    };

    test('tryFrom returns an AnalysedDish for a modifiable verdict', () {
      // Arrange & Act
      final result = AnalysedDish.tryFrom(modifiableJson);

      // Assert
      expect(result?.verdict, equals(DishVerdict.modifiable));
      expect(
        result?.modification,
        equals('Ask for a green salad instead of fries'),
      );
    });

    test(
      'tryFrom(x.toJson()) round-trips a modifiable dish to an equal value',
      () {
        // Arrange
        const dish = AnalysedDish(
          dishId: 'd1',
          name: 'Steak',
          verdict: DishVerdict.modifiable,
          why: 'Comes with fries',
          modification: 'Swap fries for salad',
          netCarbsEstimate: 8,
        );

        // Act
        final result = AnalysedDish.tryFrom(dish.toJson());

        // Assert
        expect(result, equals(dish));
      },
    );

    test(
      'tryFrom(x.toJson()) round-trips an orderAsIs dish to an equal value',
      () {
        // Arrange
        const dish = AnalysedDish(
          dishId: 'd2',
          name: 'Grilled chicken',
          verdict: DishVerdict.orderAsIs,
          why: 'Plain protein',
        );

        // Act
        final result = AnalysedDish.tryFrom(dish.toJson());

        // Assert
        expect(result, equals(dish));
      },
    );

    test('tryFrom returns null when dishId is empty', () {
      // Arrange
      final json = <String, Object?>{...orderAsIsJson, 'dishId': ''};

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when name is missing', () {
      // Arrange
      final json = <String, Object?>{...orderAsIsJson}..remove('name');

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when verdict is unparseable', () {
      // Arrange
      final json = <String, Object?>{...orderAsIsJson, 'verdict': 'unsure'};

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when why is empty', () {
      // Arrange
      final json = <String, Object?>{...orderAsIsJson, 'why': ''};

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when modifiable has no modification', () {
      // Arrange
      final json = <String, Object?>{...modifiableJson, 'modification': null};

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when modifiable has an empty modification', () {
      // Arrange
      final json = <String, Object?>{...modifiableJson, 'modification': ''};

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test(
      'tryFrom returns null when a non-modifiable dish has a modification',
      () {
        // Arrange
        final json = <String, Object?>{
          ...orderAsIsJson,
          'modification': 'Swap something',
        };

        // Act
        final result = AnalysedDish.tryFrom(json);

        // Assert
        expect(result, isNull);
      },
    );

    test('tryFrom returns null when netCarbsEstimate is not a number', () {
      // Arrange
      final json = <String, Object?>{
        ...orderAsIsJson,
        'netCarbsEstimate': 'eight',
      };

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('== returns true for dishes with equal fields', () {
      // Arrange
      final a = AnalysedDish.tryFrom(orderAsIsJson);
      final b = AnalysedDish.tryFrom(orderAsIsJson);

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for dishes differing in verdict', () {
      // Arrange
      final a = AnalysedDish.tryFrom(orderAsIsJson);
      final b = AnalysedDish.tryFrom(modifiableJson);

      // Act & Assert
      expect(a, isNot(equals(b)));
    });
  });

  group('DishRow', () {
    const dish = Dish(
      id: 'd1',
      name: 'Steak',
      description: '',
      price: 10,
      options: [],
    );
    const analysis = AnalysedDish(
      dishId: 'd1',
      name: 'Steak',
      verdict: DishVerdict.orderAsIs,
      why: 'Plain protein',
    );

    test('== returns true for rows with equal fields', () {
      // Arrange: built at run time, so == is exercised rather than const
      // canonicalisation.
      final categories = <String>['Mains', 'Mains'];
      final a = DishRow(
        dish: dish,
        category: categories[0],
        analysis: analysis,
      );
      final b = DishRow(
        dish: dish,
        category: categories[1],
        analysis: analysis,
      );

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for rows differing in category', () {
      // Arrange
      const a = DishRow(dish: dish, category: 'Mains', analysis: analysis);
      const b = DishRow(dish: dish, category: 'Starters', analysis: analysis);

      // Act & Assert
      expect(a, isNot(equals(b)));
    });
  });

  group('LlmEngine', () {
    test('== returns true for engines with the same model', () {
      // Arrange: built at run time, so == is exercised rather than const
      // canonicalisation.
      final models = <String>['gpt-x', 'gpt-x'];
      final a = LlmEngine(model: models[0]);
      final b = LlmEngine(model: models[1]);

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toJson writes the llm discriminator', () {
      // Arrange
      const engine = LlmEngine(model: 'gpt-x');

      // Act
      final result = engine.toJson();

      // Assert
      expect(result, equals({'kind': 'llm', 'model': 'gpt-x'}));
    });
  });

  group('RulesEngine', () {
    test('== returns true for engines with the same reason', () {
      // Arrange: built at run time, so == is exercised rather than const
      // canonicalisation.
      final reasons = <MenuAnalysisFailureReason>[
        MenuAnalysisFailureReason.offline,
        MenuAnalysisFailureReason.offline,
      ];
      final a = RulesEngine(reason: reasons[0]);
      final b = RulesEngine(reason: reasons[1]);

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toJson writes the rules discriminator', () {
      // Arrange
      const engine = RulesEngine(reason: MenuAnalysisFailureReason.timeout);

      // Act
      final result = engine.toJson();

      // Assert
      expect(result, equals({'kind': 'rules', 'reason': 'timeout'}));
    });
  });

  group('MenuAnalysed', () {
    const dishJson = <String, Object?>{
      'dishId': 'd1',
      'name': 'Steak',
      'verdict': 'orderAsIs',
      'why': 'Plain protein',
      'modification': null,
      'netCarbsEstimate': null,
    };
    const llmEngineJson = <String, Object?>{'kind': 'llm', 'model': 'gpt-x'};
    const rulesEngineJson = <String, Object?>{
      'kind': 'rules',
      'reason': 'offline',
    };
    const validJson = <String, Object?>{
      'dishes': [dishJson],
      'unclassified': ['Mystery bowl'],
      'engine': llmEngineJson,
      'analysedAt': '2024-01-01T00:00:00.000Z',
    };

    test(
      'tryFrom returns a MenuAnalysed for a valid map with an LLM engine',
      () {
        // Arrange & Act
        final result = MenuAnalysed.tryFrom(validJson);

        // Assert
        expect(result?.dishes, hasLength(1));
        expect(result?.unclassified, equals(['Mystery bowl']));
        expect(result?.engine, equals(const LlmEngine(model: 'gpt-x')));
      },
    );

    test(
      'tryFrom returns a MenuAnalysed for a valid map with a rules engine',
      () {
        // Arrange
        final json = <String, Object?>{...validJson, 'engine': rulesEngineJson};

        // Act
        final result = MenuAnalysed.tryFrom(json);

        // Assert
        expect(
          result?.engine,
          equals(const RulesEngine(reason: MenuAnalysisFailureReason.offline)),
        );
      },
    );

    test('tryFrom(x.toJson()) round-trips to an equal MenuAnalysed', () {
      // Arrange
      final analysed = MenuAnalysed.tryFrom(validJson)!;

      // Act
      final result = MenuAnalysed.tryFrom(analysed.toJson());

      // Assert
      expect(result, equals(analysed));
    });

    test('tryFrom(x.toJson()) round-trips a result with a rules engine', () {
      // Arrange
      final analysed = MenuAnalysed.tryFrom(<String, Object?>{
        ...validJson,
        'engine': rulesEngineJson,
      })!;

      // Act
      final result = MenuAnalysed.tryFrom(analysed.toJson());

      // Assert
      expect(result, equals(analysed));
    });

    test('tryFrom returns null when dishes is not a List', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'dishes': 'none'};

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when a dish is malformed', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'dishes': <Object?>[
          <String, Object?>{...dishJson, 'why': ''},
        ],
      };

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when unclassified contains a non-String', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'unclassified': <Object?>[1],
      };

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when engine is not a Map', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'engine': 'llm'};

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when engine has an unknown kind', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'engine': <String, Object?>{'kind': 'guess'},
      };

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when a rules engine reason is unknown', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'engine': <String, Object?>{'kind': 'rules', 'reason': 'mystery'},
      };

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when analysedAt is unparseable', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'analysedAt': 'never'};

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom accepts empty dishes when unclassified is not empty', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'dishes': <Object?>[]};

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result?.dishes, isEmpty);
      expect(result?.unclassified, isNotEmpty);
    });

    test('copyWithEngine replaces only the engine', () {
      // Arrange
      final analysed = MenuAnalysed.tryFrom(validJson)!;
      const newEngine = RulesEngine(
        reason: MenuAnalysisFailureReason.rateLimited,
      );

      // Act
      final result = analysed.copyWithEngine(newEngine);

      // Assert
      expect(result.engine, equals(newEngine));
      expect(result.dishes, equals(analysed.dishes));
      expect(result.unclassified, equals(analysed.unclassified));
      expect(result.analysedAt, equals(analysed.analysedAt));
    });

    test('== returns true for results with equal fields', () {
      // Arrange
      final a = MenuAnalysed.tryFrom(validJson);
      final b = MenuAnalysed.tryFrom(validJson);

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for results differing in engine', () {
      // Arrange
      final a = MenuAnalysed.tryFrom(validJson);
      final b = MenuAnalysed.tryFrom(<String, Object?>{
        ...validJson,
        'engine': rulesEngineJson,
      });

      // Act & Assert
      expect(a, isNot(equals(b)));
    });

    group('options (issue #57)', () {
      const optionsJson = <String, Object?>{
        'netCarbLimitGrams': 9,
        'dietaryConstraints': ['dairy-free'],
      };
      const snapshot = AnalysisOptionsSnapshot(
        netCarbLimitGrams: 9,
        dietaryConstraints: ['dairy-free'],
      );

      test('tryFrom reads a recorded options snapshot', () {
        // Arrange
        final json = <String, Object?>{...validJson, 'options': optionsJson};

        // Act
        final result = MenuAnalysed.tryFrom(json);

        // Assert
        expect(result?.options, equals(snapshot));
      });

      test('tryFrom reads a result cached before issue #57, with no '
          'options key, as null options rather than rejecting it', () {
        // Act
        final result = MenuAnalysed.tryFrom(validJson);

        // Assert
        expect(result, isNotNull);
        expect(result!.options, isNull);
      });

      test('tryFrom reads an explicit null options as null', () {
        // Arrange
        final json = <String, Object?>{...validJson, 'options': null};

        // Act
        final result = MenuAnalysed.tryFrom(json);

        // Assert
        expect(result, isNotNull);
        expect(result!.options, isNull);
      });

      test('tryFrom returns null when options is not a map', () {
        // Arrange
        final json = <String, Object?>{...validJson, 'options': 'six'};

        // Act & Assert
        expect(MenuAnalysed.tryFrom(json), isNull);
      });

      test('tryFrom returns null when options is a malformed map', () {
        // Arrange
        final json = <String, Object?>{
          ...validJson,
          'options': <String, Object?>{'netCarbLimitGrams': 'six'},
        };

        // Act & Assert
        expect(MenuAnalysed.tryFrom(json), isNull);
      });

      test('tryFrom(x.toJson()) round-trips a result with options', () {
        // Arrange
        final analysed = MenuAnalysed.tryFrom(validJson)!
            .copyWithOptions(snapshot);

        // Act
        final result = MenuAnalysed.tryFrom(analysed.toJson());

        // Assert
        expect(result, equals(analysed));
        expect(result!.options, equals(snapshot));
      });

      test('copyWithOptions replaces only the options', () {
        // Arrange
        final analysed = MenuAnalysed.tryFrom(validJson)!;

        // Act
        final result = analysed.copyWithOptions(snapshot);

        // Assert
        expect(result.options, equals(snapshot));
        expect(result.dishes, equals(analysed.dishes));
        expect(result.unclassified, equals(analysed.unclassified));
        expect(result.engine, equals(analysed.engine));
        expect(result.analysedAt, equals(analysed.analysedAt));
      });

      test('copyWithEngine keeps the options', () {
        // Arrange
        final analysed = MenuAnalysed.tryFrom(validJson)!
            .copyWithOptions(snapshot);

        // Act
        final result = analysed.copyWithEngine(
          const RulesEngine(reason: MenuAnalysisFailureReason.offline),
        );

        // Assert
        expect(result.options, equals(snapshot));
      });

      test('== returns false for results differing only in options', () {
        // Arrange
        final a = MenuAnalysed.tryFrom(validJson)!;
        final b = a.copyWithOptions(snapshot);

        // Act & Assert
        expect(a, isNot(equals(b)));
      });
    });
  });

  group('AnalysisOptionsSnapshot', () {
    test('defaults to no dietary constraints', () {
      // Arrange
      const snapshot = AnalysisOptionsSnapshot(netCarbLimitGrams: 6);

      // Assert
      expect(snapshot.dietaryConstraints, isEmpty);
    });

    test('tryFrom(x.toJson()) round-trips a snapshot', () {
      // Arrange
      const snapshot = AnalysisOptionsSnapshot(
        netCarbLimitGrams: 12,
        dietaryConstraints: ['seed-oil free', 'carnivore'],
      );

      // Act
      final result = AnalysisOptionsSnapshot.tryFrom(snapshot.toJson());

      // Assert
      expect(result, equals(snapshot));
    });

    test('tryFrom reads a missing dietaryConstraints as none', () {
      // Act
      final result = AnalysisOptionsSnapshot.tryFrom(<String, Object?>{
        'netCarbLimitGrams': 6,
      });

      // Assert
      expect(
        result,
        equals(const AnalysisOptionsSnapshot(netCarbLimitGrams: 6)),
      );
    });

    test('tryFrom returns null when netCarbLimitGrams is missing', () {
      // Act & Assert
      expect(AnalysisOptionsSnapshot.tryFrom(<String, Object?>{}), isNull);
    });

    test('tryFrom returns null when netCarbLimitGrams is not an int', () {
      // Act & Assert
      expect(
        AnalysisOptionsSnapshot.tryFrom(<String, Object?>{
          'netCarbLimitGrams': 6.5,
        }),
        isNull,
      );
    });

    test('tryFrom returns null when dietaryConstraints is not a list', () {
      // Act & Assert
      expect(
        AnalysisOptionsSnapshot.tryFrom(<String, Object?>{
          'netCarbLimitGrams': 6,
          'dietaryConstraints': 'dairy-free',
        }),
        isNull,
      );
    });

    test('tryFrom returns null when a dietary constraint is not a '
        'string', () {
      // Act & Assert
      expect(
        AnalysisOptionsSnapshot.tryFrom(<String, Object?>{
          'netCarbLimitGrams': 6,
          'dietaryConstraints': <Object?>['dairy-free', 3],
        }),
        isNull,
      );
    });

    test('== compares the limit and the constraints element-wise', () {
      // Arrange
      const a = AnalysisOptionsSnapshot(
        netCarbLimitGrams: 6,
        dietaryConstraints: ['dairy-free'],
      );
      const b = AnalysisOptionsSnapshot(
        netCarbLimitGrams: 6,
        dietaryConstraints: ['dairy-free'],
      );
      const differentLimit = AnalysisOptionsSnapshot(
        netCarbLimitGrams: 7,
        dietaryConstraints: ['dairy-free'],
      );
      const differentLength = AnalysisOptionsSnapshot(
        netCarbLimitGrams: 6,
        dietaryConstraints: ['dairy-free', 'carnivore'],
      );
      const differentConstraint = AnalysisOptionsSnapshot(
        netCarbLimitGrams: 6,
        dietaryConstraints: ['carnivore'],
      );

      // Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(differentLimit)));
      expect(a, isNot(equals(differentLength)));
      expect(a, isNot(equals(differentConstraint)));
    });
  });

  group('MenuAnalysisFailed', () {
    test('toJson writes the reason and detail', () {
      // Arrange
      const failure = MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.badResponse,
        detail: 'HTTP 500',
      );

      // Act
      final result = failure.toJson();

      // Assert
      expect(result, equals({'reason': 'badResponse', 'detail': 'HTTP 500'}));
    });

    test('== returns true for failures with equal fields', () {
      // Arrange: built at run time, so == is exercised rather than const
      // canonicalisation.
      final reasons = <MenuAnalysisFailureReason>[
        MenuAnalysisFailureReason.backendUnreachable,
        MenuAnalysisFailureReason.backendUnreachable,
      ];
      final a = MenuAnalysisFailed(reason: reasons[0]);
      final b = MenuAnalysisFailed(reason: reasons[1]);

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for failures differing in detail', () {
      // Arrange
      const a = MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.badResponse,
        detail: 'HTTP 500',
      );
      const b = MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.badResponse,
        detail: 'HTTP 502',
      );

      // Act & Assert
      expect(a, isNot(equals(b)));
    });
  });

  group('MenuAnalysis (sealed)', () {
    test('a switch over MenuAnalysis needs no fallback branch', () {
      // Arrange
      const MenuAnalysis analysis = MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.offline,
      );

      // Act
      //
      // Exhaustive: MenuAnalysis is sealed over exactly MenuAnalysed and
      // MenuAnalysisFailed, so the analyzer proves this switch covers every
      // case at compile time. Deleting either case below, or adding a new
      // MenuAnalysis subclass without a case for it, fails the build with
      // "non_exhaustive_switch_statement" rather than failing at runtime.
      final kind = switch (analysis) {
        MenuAnalysed() => 'analysed',
        MenuAnalysisFailed() => 'failed',
      };

      // Assert
      expect(kind, equals('failed'));
    });
  });

  group('AnalysisEngine (sealed)', () {
    test('a switch over AnalysisEngine needs no fallback branch', () {
      // Arrange
      const AnalysisEngine engine = LlmEngine(model: 'nex-agi/nex-n2.5-pro');

      // Act
      //
      // Exhaustive: AnalysisEngine is sealed over exactly LlmEngine and
      // RulesEngine, so the analyzer proves this switch covers every case
      // at compile time; a missing case fails the build, not a test run.
      final kind = switch (engine) {
        LlmEngine() => 'llm',
        RulesEngine() => 'rules',
      };

      // Assert
      expect(kind, equals('llm'));
    });
  });

  // ---------------------------------------------------------------------------
  // HiddenCarb (issue #213)
  // ---------------------------------------------------------------------------

  group('HiddenCarbCertainty', () {
    test('tryParse returns suspected for the wire value "suspected"', () {
      expect(
        HiddenCarbCertainty.tryParse('suspected'),
        equals(HiddenCarbCertainty.suspected),
      );
    });

    test('tryParse returns likely for the wire value "likely"', () {
      expect(
        HiddenCarbCertainty.tryParse('likely'),
        equals(HiddenCarbCertainty.likely),
      );
    });

    test('tryParse returns null for an unknown string', () {
      expect(HiddenCarbCertainty.tryParse('unknown'), isNull);
    });
  });

  group('HiddenCarb', () {
    const validJson = <String, Object?>{
      'source': 'house dressing',
      'certainty': 'suspected',
      'waiterQuestion': 'Is the dressing sugar-free?',
    };

    test('tryFrom returns a HiddenCarb for a valid map', () {
      // Act
      final result = HiddenCarb.tryFrom(validJson);

      // Assert
      expect(result, isNotNull);
      expect(result!.source, equals('house dressing'));
      expect(result.certainty, equals(HiddenCarbCertainty.suspected));
      expect(result.waiterQuestion, equals('Is the dressing sugar-free?'));
    });

    test('tryFrom(x.toJson()) round-trips to an equal HiddenCarb', () {
      // Arrange
      const flag = HiddenCarb(
        source: 'teriyaki glaze',
        certainty: HiddenCarbCertainty.likely,
        waiterQuestion: 'Is the glaze without honey?',
      );

      // Act
      final result = HiddenCarb.tryFrom(flag.toJson());

      // Assert
      expect(result, equals(flag));
    });

    test('tryFrom returns null when source is blank', () {
      final json = <String, Object?>{...validJson, 'source': '  '};
      expect(HiddenCarb.tryFrom(json), isNull);
    });

    test('tryFrom returns null when certainty is unknown', () {
      final json = <String, Object?>{...validJson, 'certainty': 'maybe'};
      expect(HiddenCarb.tryFrom(json), isNull);
    });

    test('tryFrom returns null when waiterQuestion is blank', () {
      final json = <String, Object?>{...validJson, 'waiterQuestion': ''};
      expect(HiddenCarb.tryFrom(json), isNull);
    });

    test('tryFrom returns null when source is missing', () {
      final json = <String, Object?>{...validJson}..remove('source');
      expect(HiddenCarb.tryFrom(json), isNull);
    });

    test('== and hashCode compare all three fields', () {
      const a = HiddenCarb(
        source: 'house dressing',
        certainty: HiddenCarbCertainty.suspected,
        waiterQuestion: 'Is the dressing sugar-free?',
      );
      const b = HiddenCarb(
        source: 'house dressing',
        certainty: HiddenCarbCertainty.suspected,
        waiterQuestion: 'Is the dressing sugar-free?',
      );
      const c = HiddenCarb(
        source: 'teriyaki glaze',
        certainty: HiddenCarbCertainty.likely,
        waiterQuestion: 'Glaze without honey?',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('AnalysedDish with hiddenCarbs (issue #213)', () {
    const dishWithFlagJson = <String, Object?>{
      'dishId': 'd10',
      'name': 'Grilled salmon',
      'verdict': 'modifiable',
      'why': 'House glaze',
      'modification': 'Ask for the glaze on the side',
      'netCarbsEstimate': null,
      'hiddenCarbs': [
        <String, Object?>{
          'source': 'house glaze',
          'certainty': 'likely',
          'waiterQuestion': 'Is the glaze without sugar?',
        },
      ],
    };

    test('tryFrom reads hiddenCarbs when present', () {
      // Act
      final result = AnalysedDish.tryFrom(dishWithFlagJson);

      // Assert
      expect(result?.hiddenCarbs, hasLength(1));
      expect(result?.hiddenCarbs.first.source, equals('house glaze'));
    });

    test('tryFrom reads absent hiddenCarbs as empty list', () {
      // Arrange — no hiddenCarbs key (pre-issue-#213 cache entry)
      const json = <String, Object?>{
        'dishId': 'd2',
        'name': 'Grilled chicken',
        'verdict': 'orderAsIs',
        'why': 'Plain protein',
        'modification': null,
        'netCarbsEstimate': null,
      };

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert
      expect(result, isNotNull);
      expect(result!.hiddenCarbs, isEmpty);
    });

    test('tryFrom drops a malformed entry in hiddenCarbs silently', () {
      // Arrange — one valid entry and one missing the source
      final json = <String, Object?>{
        ...dishWithFlagJson,
        'hiddenCarbs': <Object?>[
          <String, Object?>{
            'certainty': 'likely',
            'waiterQuestion': 'Sugar-free?',
          },
          <String, Object?>{
            'source': 'house glaze',
            'certainty': 'likely',
            'waiterQuestion': 'Is the glaze without sugar?',
          },
        ],
      };

      // Act
      final result = AnalysedDish.tryFrom(json);

      // Assert — only the valid entry survives
      expect(result, isNotNull);
      expect(result!.hiddenCarbs, hasLength(1));
      expect(result.hiddenCarbs.first.source, equals('house glaze'));
    });

    test('tryFrom(x.toJson()) round-trips a dish with hidden carbs', () {
      // Arrange
      final dish = AnalysedDish.tryFrom(dishWithFlagJson)!;

      // Act
      final result = AnalysedDish.tryFrom(dish.toJson());

      // Assert
      expect(result, equals(dish));
      expect(result!.hiddenCarbs, equals(dish.hiddenCarbs));
    });

    test('== accounts for hiddenCarbs list', () {
      final a = AnalysedDish.tryFrom(dishWithFlagJson)!;
      final b = AnalysedDish.tryFrom(dishWithFlagJson)!;
      const noFlags = AnalysedDish(
        dishId: 'd10',
        name: 'Grilled salmon',
        verdict: DishVerdict.modifiable,
        why: 'House glaze',
        modification: 'Ask for the glaze on the side',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(noFlags)));
    });
  });

  group('MenuAnalysed schemaVersion (issue #213)', () {
    const llmEngineJson = <String, Object?>{'kind': 'llm', 'model': 'gpt-x'};
    const baseJson = <String, Object?>{
      'dishes': <Object?>[],
      'unclassified': <Object?>[],
      'engine': llmEngineJson,
      'analysedAt': '2024-01-01T00:00:00.000Z',
    };

    test('tryFrom reads an absent schemaVersion as 0', () {
      // Act
      final result = MenuAnalysed.tryFrom(baseJson);

      // Assert
      expect(result, isNotNull);
      expect(result!.schemaVersion, equals(0));
    });

    test('tryFrom reads an explicit schemaVersion of 1', () {
      // Arrange
      final json = <String, Object?>{...baseJson, 'schemaVersion': 1};

      // Act
      final result = MenuAnalysed.tryFrom(json);

      // Assert
      expect(result?.schemaVersion, equals(1));
    });

    test('toJson always emits schemaVersion', () {
      // Arrange
      final json = <String, Object?>{...baseJson, 'schemaVersion': 1};
      final analysed = MenuAnalysed.tryFrom(json)!;

      // Act
      final serialised = analysed.toJson();

      // Assert
      expect(serialised.containsKey('schemaVersion'), isTrue);
      expect(serialised['schemaVersion'], equals(1));
    });

    test('toJson emits schemaVersion 0 when default', () {
      // Act
      final analysed = MenuAnalysed.tryFrom(baseJson)!;
      final serialised = analysed.toJson();

      // Assert
      expect(serialised.containsKey('schemaVersion'), isTrue);
      expect(serialised['schemaVersion'], equals(0));
    });

    test('tryFrom(x.toJson()) round-trips schemaVersion', () {
      // Arrange
      final json = <String, Object?>{...baseJson, 'schemaVersion': 1};
      final analysed = MenuAnalysed.tryFrom(json)!;

      // Act
      final result = MenuAnalysed.tryFrom(analysed.toJson());

      // Assert
      expect(result?.schemaVersion, equals(1));
    });

    test('== accounts for schemaVersion', () {
      final a = MenuAnalysed.tryFrom(baseJson)!; // schemaVersion = 0
      final b = MenuAnalysed.tryFrom(<String, Object?>{
        ...baseJson,
        'schemaVersion': 1,
      })!;

      expect(a, isNot(equals(b)));
    });
  });
}
