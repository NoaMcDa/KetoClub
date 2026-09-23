import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/constants.dart';

void main() {
  group('appName', () {
    test('appName is KetoClub', () {
      // Arrange, Act: appName is a compile-time constant.
      // Assert
      expect(appName, equals('KetoClub'));
    });
  });

  group('browserUserAgent', () {
    test('browserUserAgent looks like a real Chrome desktop UA', () {
      // Arrange, Act: browserUserAgent is a compile-time constant.
      // Assert
      expect(browserUserAgent, contains('Mozilla/5.0'));
      expect(browserUserAgent, contains('Chrome/120'));
      expect(browserUserAgent, contains('AppleWebKit'));
    });
  });

  group('cache and LLM tuning constants', () {
    test('menuCacheTtl is 24 hours', () {
      // Assert
      expect(menuCacheTtl, equals(const Duration(hours: 24)));
    });

    test('llmRequestTimeout is 120 seconds', () {
      // Assert
      expect(llmRequestTimeout, equals(const Duration(seconds: 120)));
    });

    test('maxAnalysedDishes is 150', () {
      // Assert
      expect(maxAnalysedDishes, equals(150));
    });

    test('maxWhyLength is 300', () {
      // Assert
      expect(maxWhyLength, equals(300));
    });

    test('maxModificationLength is 300', () {
      // Assert
      expect(maxModificationLength, equals(300));
    });

    test('minOverlapWordLength is 3', () {
      // Assert
      expect(minOverlapWordLength, equals(3));
    });
  });

  group('prompt text', () {
    test('promptVerdictDefinitionsTemplate names all three verdicts', () {
      // Assert
      expect(promptVerdictDefinitionsTemplate, contains('orderAsIs'));
      expect(promptVerdictDefinitionsTemplate, contains('modifiable'));
      expect(promptVerdictDefinitionsTemplate, contains('nonKeto'));
    });

    test('both templates carry the limit placeholder and no fixed figure', () {
      // Assert: the green threshold is the placeholder, never a
      // hard-coded 6g the user's limit would silently fail to replace.
      expect(promptVerdictDefinitionsTemplate, contains('{limit}g or less'));
      expect(promptKetoRulesTemplate, contains('{limit}g or less'));
      expect(promptVerdictDefinitionsTemplate, isNot(contains('6g')));
      expect(promptKetoRulesTemplate, isNot(contains('6g')));
    });

    test('promptKetoRulesFor states the given net-carb threshold', () {
      // Act
      final rules = promptKetoRulesFor(12);

      // Assert
      expect(rules, contains('Net carbs of 12g or less per dish'));
      expect(rules, isNot(contains(netCarbLimitPlaceholder)));
    });

    test('promptVerdictDefinitionsFor states the given threshold in the '
        'green definition only', () {
      // Act
      final lines = promptVerdictDefinitionsFor(4).split('\n');

      // Assert: still one line per verdict, which the legend relies on.
      expect(lines, hasLength(3));
      expect(lines[0], contains('net carbohydrates 4g or less'));
      expect(lines[1], isNot(contains('4g')));
      expect(lines[2], isNot(contains('4g')));
    });

    test('at the default limit both texts read exactly as the fixed-6g '
        'prompt did, so the default chat-cache key is unchanged', () {
      // Act
      final definitions = promptVerdictDefinitionsFor(defaultNetCarbLimitGrams);
      final rules = promptKetoRulesFor(defaultNetCarbLimitGrams);

      // Assert
      expect(
        definitions,
        startsWith(
          'orderAsIs — net carbohydrates 6g or less, a healthy '
          'fat-and-protein base,',
        ),
      );
      expect(
        rules,
        startsWith(
          'Net carbs of 6g or less per dish make it green (orderAsIs).\n',
        ),
      );
    });
  });

  group('net carb limit', () {
    test('the default is 6 g inside a 2..25 g range', () {
      // Assert
      expect(defaultNetCarbLimitGrams, equals(6));
      expect(minNetCarbLimitGrams, equals(2));
      expect(maxNetCarbLimitGrams, equals(25));
    });

    test('clampNetCarbLimitGrams keeps an in-range value', () {
      // Assert
      expect(clampNetCarbLimitGrams(2), equals(2));
      expect(clampNetCarbLimitGrams(9), equals(9));
      expect(clampNetCarbLimitGrams(25), equals(25));
    });

    test('clampNetCarbLimitGrams pulls an out-of-range value to the '
        'nearest bound', () {
      // Assert
      expect(clampNetCarbLimitGrams(1), equals(minNetCarbLimitGrams));
      expect(clampNetCarbLimitGrams(-40), equals(minNetCarbLimitGrams));
      expect(clampNetCarbLimitGrams(26), equals(maxNetCarbLimitGrams));
      expect(clampNetCarbLimitGrams(1000), equals(maxNetCarbLimitGrams));
    });
  });

  group('why strings', () {
    test('greenWhyEn and greenWhyHe are non-empty', () {
      // Assert
      expect(greenWhyEn, isNotEmpty);
      expect(greenWhyHe, isNotEmpty);
    });

    test('yellowWhyEn and yellowWhyHe are non-empty', () {
      // Assert
      expect(yellowWhyEn, isNotEmpty);
      expect(yellowWhyHe, isNotEmpty);
    });

    test('redWhyEn and redWhyHe carry the {base} placeholder', () {
      // Assert
      expect(redWhyEn, contains('{base}'));
      expect(redWhyHe, contains('{base}'));
    });
  });

  group('carbModifiersEn', () {
    test('has 58 triggers', () {
      // Assert
      expect(carbModifiersEn, hasLength(58));
    });

    test('every trigger maps to a non-empty sentence', () {
      // Arrange, Act, Assert
      for (final entry in carbModifiersEn.entries) {
        expect(
          entry.value,
          isNotEmpty,
          reason: 'carbModifiersEn["${entry.key}"] must not be empty',
        );
      }
    });

    test('every trigger key is lower-case and trimmed', () {
      // Arrange, Act, Assert
      for (final key in carbModifiersEn.keys) {
        expect(
          key,
          equals(key.toLowerCase().trim()),
          reason: 'carbModifiersEn key "$key" must be lower-case & trimmed',
        );
      }
    });
  });

  group('carbModifiersHe', () {
    test('has 75 triggers', () {
      // Assert
      expect(carbModifiersHe, hasLength(75));
    });

    test('every trigger maps to a non-empty sentence', () {
      // Arrange, Act, Assert
      for (final entry in carbModifiersHe.entries) {
        expect(
          entry.value,
          isNotEmpty,
          reason: 'carbModifiersHe["${entry.key}"] must not be empty',
        );
      }
    });

    test('#12 audit: maple and balsamic glaze have a Hebrew counterpart', () {
      // Assert: these two English carbModifiersEn triggers had no Hebrew
      // equivalent at all before the #12 audit.
      expect(carbModifiersHe, contains('מייפל'));
      expect(carbModifiersHe, contains('זיגוג בלסמי'));
    });

    test('#12 audit: ראפ ("wrap") is a carb modifier (yellow), matching '
        'its English counterpart wrap, not a non-keto base (red)', () {
      // Assert: D-V3 treats bread that merely carries a dish (a bun, a
      // pita, a tortilla, a wrap) as removable and yellow, never red.
      expect(carbModifiersHe, contains('ראפ'));
      expect(nonKetoBasesHe, isNot(contains('ראפ')));
    });
  });

  group('nonKetoBasesEn', () {
    test('has 92 triggers', () {
      // Assert
      expect(nonKetoBasesEn, hasLength(92));
    });

    test('carries the battered-fish phrases D-V2 alone would miss', () {
      // Assert: "fish and chips" names no breading word, so without these it
      // returned YELLOW "replace the chips" and left the batter.
      expect(nonKetoBasesEn, contains('fish and chips'));
      expect(nonKetoBasesEn, contains('fish chips'));
    });

    test('does not carry a bare brioche trigger', () {
      // Assert: as a red base it overrode D-V3 and turned every burger on a
      // brioche bun red and hidden.
      expect(nonKetoBasesEn, isNot(contains('brioche')));
    });

    test('has no duplicate triggers', () {
      // Arrange
      final unique = nonKetoBasesEn.toSet();
      // Assert
      expect(unique, hasLength(nonKetoBasesEn.length));
    });

    test('every trigger is non-empty and lower-case', () {
      // Arrange, Act, Assert
      for (final trigger in nonKetoBasesEn) {
        expect(trigger, isNotEmpty);
        expect(
          trigger,
          equals(trigger.toLowerCase()),
          reason: 'nonKetoBasesEn trigger "$trigger" must be lower-case',
        );
      }
    });
  });

  group('nonKetoBasesHe', () {
    test('has 107 triggers', () {
      // Assert
      expect(nonKetoBasesHe, hasLength(107));
    });

    test('has no duplicate triggers', () {
      // Arrange
      final unique = nonKetoBasesHe.toSet();
      // Assert
      expect(unique, hasLength(nonKetoBasesHe.length));
    });

    test('does not contain a bare penne transliteration', () {
      // Assert: פנה is an ordinary Hebrew word ("turned"); see the doc
      // comment on nonKetoBasesHe for why it is deliberately absent.
      expect(nonKetoBasesHe, isNot(contains('פנה')));
    });

    test('#12 audit: every English trigger that had no Hebrew counterpart '
        'now has one', () {
      // Assert: found by enumerating nonKetoBasesEn against
      // nonKetoBasesHe during the #12 audit — each of these had no
      // Hebrew equivalent at all (`fish and chips`/`fish chips`,
      // `pancake(s)`, `waffle(s)`, `katsu`, `milanese`, `macaroni`,
      // `mac and cheese`, `polenta`, `grits`, `empanada`, `gyoza`,
      // `bao`, `arancini`, `croquette`, `pie`, `burrito`, `quesadilla`,
      // `taco shell`), the exact silent-vocabulary-gap failure mode
      // CLAUDE.md warns about.
      expect(nonKetoBasesHe, contains("פיש אנד צ'יפס"));
      expect(nonKetoBasesHe, contains("דג וצ'יפס"));
      expect(nonKetoBasesHe, contains('פנקייק'));
      expect(nonKetoBasesHe, contains('פנקייקים'));
      expect(nonKetoBasesHe, contains('וופל'));
      expect(nonKetoBasesHe, contains('וופלים'));
      expect(nonKetoBasesHe, contains('קטסו'));
      expect(nonKetoBasesHe, contains('מילנז'));
      expect(nonKetoBasesHe, contains('מקרוני'));
      expect(nonKetoBasesHe, contains("מק אנד צ'יז"));
      expect(nonKetoBasesHe, contains('פולנטה'));
      expect(nonKetoBasesHe, contains('גריטס'));
      expect(nonKetoBasesHe, contains('אמפנדה'));
      expect(nonKetoBasesHe, contains('גיוזה'));
      expect(nonKetoBasesHe, contains('באו'));
      expect(nonKetoBasesHe, contains("ארנצ'יני"));
      expect(nonKetoBasesHe, contains('קרוקט'));
      expect(nonKetoBasesHe, contains('פאי'));
      expect(nonKetoBasesHe, contains('בוריטו'));
      expect(nonKetoBasesHe, contains('קסדיה'));
      expect(nonKetoBasesHe, contains('קליפת טאקו'));
    });
  });

  group('nonKetoBaseLabelsEn', () {
    test('every label key is an actual nonKetoBasesEn trigger', () {
      // Arrange, Act, Assert
      for (final key in nonKetoBaseLabelsEn.keys) {
        expect(
          nonKetoBasesEn,
          contains(key),
          reason: 'nonKetoBaseLabelsEn["$key"] has no matching trigger',
        );
      }
    });

    test('noodle is labelled noodles and battered fish is named', () {
      // Assert
      expect(nonKetoBaseLabelsEn['noodle'], equals('noodles'));
      expect(nonKetoBaseLabelsEn['fish and chips'], equals('battered fish'));
    });
  });

  group('nonKetoBaseLabelsHe', () {
    test('every label key is an actual nonKetoBasesHe trigger', () {
      // Arrange, Act, Assert
      for (final key in nonKetoBaseLabelsHe.keys) {
        expect(
          nonKetoBasesHe,
          contains(key),
          reason: 'nonKetoBaseLabelsHe["$key"] has no matching trigger',
        );
      }
    });

    test('does not label לחמניות (a carb modifier, never a red base)', () {
      // Assert
      expect(nonKetoBaseLabelsHe, isNot(contains('לחמניות')));
    });
  });

  group('ketoQualifierGuardsEn', () {
    test('every guarded key is a real trigger', () {
      // Arrange
      final allTriggers = <String>{...carbModifiersEn.keys, ...nonKetoBasesEn};
      // Act, Assert
      for (final key in ketoQualifierGuardsEn.keys) {
        expect(
          allTriggers,
          contains(key),
          reason: 'ketoQualifierGuardsEn["$key"] has no matching trigger',
        );
      }
    });

    test('does not guard corn (baby corn is a genuine trap)', () {
      // Assert
      expect(ketoQualifierGuardsEn, isNot(contains('corn')));
    });

    test('spaghetti is guarded only after, by squash', () {
      // Act
      final guard = ketoQualifierGuardsEn['spaghetti'];
      // Assert
      expect(guard, isNotNull);
      expect(guard!.before, isEmpty);
      expect(guard.after, contains('squash'));
    });
  });

  group('ketoQualifierGuardsHe', () {
    test('every guarded key is a real trigger', () {
      // Arrange
      final allTriggers = <String>{...carbModifiersHe.keys, ...nonKetoBasesHe};
      // Act, Assert
      for (final key in ketoQualifierGuardsHe.keys) {
        expect(
          allTriggers,
          contains(key),
          reason: 'ketoQualifierGuardsHe["$key"] has no matching trigger',
        );
      }
    });

    test('every guard is bidirectional (before equals after)', () {
      // Act, Assert
      for (final entry in ketoQualifierGuardsHe.entries) {
        expect(
          entry.value.before,
          equals(entry.value.after),
          reason: 'ketoQualifierGuardsHe["${entry.key}"] must be symmetric',
        );
      }
    });
  });

  group('triggerSuppresses', () {
    test('every English suppressor key is a real carbModifiersEn trigger', () {
      // Arrange, Act, Assert
      for (final key in triggerSuppresses.keys) {
        final isEnglish = carbModifiersEn.containsKey(key);
        final isHebrew = carbModifiersHe.containsKey(key);
        expect(
          isEnglish || isHebrew,
          isTrue,
          reason: 'triggerSuppresses["$key"] has no matching trigger',
        );
      }
    });

    test('every victim is a real carbModifiers trigger, in the same '
        'language as its suppressor', () {
      // Arrange, Act, Assert
      for (final entry in triggerSuppresses.entries) {
        final suppressorIsEnglish = carbModifiersEn.containsKey(entry.key);
        final victims =
            carbModifiersHe.containsKey(entry.key) && !suppressorIsEnglish
            ? carbModifiersHe
            : carbModifiersEn;
        for (final victim in entry.value) {
          expect(
            victims,
            contains(victim),
            reason:
                'triggerSuppresses["${entry.key}"] names unknown victim '
                '"$victim"',
          );
        }
      }
    });

    test('sweet potato and sweet potatoes both suppress bare potato', () {
      // Assert
      expect(
        triggerSuppresses['sweet potato'],
        containsAll(['potato', 'potatoes']),
      );
      expect(
        triggerSuppresses['sweet potatoes'],
        containsAll(['potato', 'potatoes']),
      );
    });

    test('דבש תמרים suppresses bare דבש', () {
      // Assert
      expect(triggerSuppresses['דבש תמרים'], equals(['דבש']));
    });
  });

  group('dietary rule toggles (issue #56)', () {
    /// A Hebrew letter, to tell which language a sentence is in.
    final hebrewLetter = RegExp('[א-ת]');

    test('the three prompt fragments are distinct, one-line and English', () {
      // Arrange
      const fragments = [
        seedOilFreePromptFragment,
        dairyFreePromptFragment,
        carnivoreOnlyPromptFragment,
      ];

      // Assert
      expect(fragments.toSet(), hasLength(3));
      for (final fragment in fragments) {
        expect(fragment.trim(), isNotEmpty);
        expect(fragment, isNot(contains('\n')));
        expect(hebrewLetter.hasMatch(fragment), isFalse);
      }
    });

    test('each fragment names its rule and the verdicts it asks for', () {
      // Assert
      expect(seedOilFreePromptFragment, startsWith('Strict seed-oil free:'));
      expect(dairyFreePromptFragment, startsWith('Dairy-free keto:'));
      expect(carnivoreOnlyPromptFragment, startsWith('Carnivore only:'));
      for (final fragment in [
        seedOilFreePromptFragment,
        dairyFreePromptFragment,
        carnivoreOnlyPromptFragment,
      ]) {
        expect(fragment, contains('modifiable'));
        expect(fragment, contains('nonKeto'));
      }
    });

    test('every waiter sentence is non-empty, within the modification '
        'limit, and in its own language', () {
      // Arrange
      const english = [
        seedOilFreeModificationEn,
        dairyFreeModificationEn,
        carnivoreOnlyModificationEn,
        dietaryRuleWhyEn,
      ];
      const hebrew = [
        seedOilFreeModificationHe,
        dairyFreeModificationHe,
        carnivoreOnlyModificationHe,
        dietaryRuleWhyHe,
      ];

      // Assert
      for (final sentence in [...english, ...hebrew]) {
        expect(sentence.trim(), isNotEmpty);
        expect(sentence.length, lessThanOrEqualTo(maxModificationLength));
      }
      for (final sentence in english) {
        expect(hebrewLetter.hasMatch(sentence), isFalse, reason: sentence);
      }
      for (final sentence in hebrew) {
        expect(hebrewLetter.hasMatch(sentence), isTrue, reason: sentence);
      }
    });

    test('every trigger list is non-empty, trimmed and free of '
        'duplicates', () {
      // Arrange
      const lists = {
        'seedOilTriggersEn': seedOilTriggersEn,
        'seedOilTriggersHe': seedOilTriggersHe,
        'dairyTriggersEn': dairyTriggersEn,
        'dairyTriggersHe': dairyTriggersHe,
        'plantTriggersEn': plantTriggersEn,
        'plantTriggersHe': plantTriggersHe,
      };

      // Assert
      for (final MapEntry(key: name, value: triggers) in lists.entries) {
        expect(triggers, isNotEmpty, reason: name);
        expect(triggers.toSet(), hasLength(triggers.length), reason: name);
        for (final trigger in triggers) {
          expect(trigger, isNotEmpty, reason: name);
          expect(trigger, equals(trigger.trim()), reason: name);
        }
      }
    });

    test('the English trigger lists are lower-case and hold no Hebrew', () {
      // Assert
      for (final trigger in [
        ...seedOilTriggersEn,
        ...dairyTriggersEn,
        ...plantTriggersEn,
      ]) {
        expect(trigger, equals(trigger.toLowerCase()));
        expect(hebrewLetter.hasMatch(trigger), isFalse, reason: trigger);
      }
    });

    test('the Hebrew trigger lists are all Hebrew', () {
      // Assert
      for (final trigger in [
        ...seedOilTriggersHe,
        ...dairyTriggersHe,
        ...plantTriggersHe,
      ]) {
        expect(hebrewLetter.hasMatch(trigger), isTrue, reason: trigger);
      }
    });

    test('every dairy guard key is itself a dairy trigger', () {
      // Assert
      expect(dairyTriggersEn, containsAll(dairyGuardsEn.keys));
      expect(dairyTriggersHe, containsAll(dairyGuardsHe.keys));
    });
  });
}
