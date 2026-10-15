import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

/// Every enum value's wire name, in declaration order.
List<String> _names(List<Enum> values) => [for (final v in values) v.name];

void main() {
  group('the enums', () {
    test('pin their wire names in order', () {
      expect(_names(ConcernSource.values), [
        'name',
        'description',
        'option',
        'hidden',
        'model',
        'kitchen',
        'matrix',
      ]);
      expect(_names(Certainty.values), ['stated', 'likely', 'suspected']);
      expect(_names(EvidenceTier.values), [
        'declared',
        'stated',
        'inferred',
        'suspected',
        'confirmed',
        'denied',
      ]);
      expect(_names(ComponentRole.values), [
        'base',
        'protein',
        'side',
        'sauce',
        'garnish',
        'option',
        'unknown',
      ]);
    });

    test("Certainty has exactly the vocabulary's TriggerCertainty names, so "
        'a trigger converts by name', () {
      expect(_names(Certainty.values), _names(TriggerCertainty.values));
      for (final trigger in TriggerCertainty.values) {
        expect(Certainty.tryParse(trigger.name)?.name, trigger.name);
      }
    });

    test('tryParse matches by name and returns null for anything else', () {
      for (final value in ConcernSource.values) {
        expect(ConcernSource.tryParse(value.name), value);
      }
      for (final value in Certainty.values) {
        expect(Certainty.tryParse(value.name), value);
      }
      for (final value in EvidenceTier.values) {
        expect(EvidenceTier.tryParse(value.name), value);
      }
      for (final value in ComponentRole.values) {
        expect(ComponentRole.tryParse(value.name), value);
      }
      expect(ConcernSource.tryParse('rules'), isNull);
      expect(Certainty.tryParse('Stated'), isNull);
      expect(EvidenceTier.tryParse(''), isNull);
      expect(ComponentRole.tryParse('topping'), isNull);
    });
  });

  group('Concern', () {
    const full = Concern(
      restrictionId: RestrictionId.sesame,
      source: ConcernSource.description,
      certainty: Certainty.stated,
      tier: EvidenceTier.stated,
      matchedText: 'טחינה',
      waiterQuestion: 'האם יש טחינה ברוטב?',
    );
    const bare = Concern(
      restrictionId: RestrictionId.wheat,
      source: ConcernSource.hidden,
      certainty: Certainty.likely,
      tier: EvidenceTier.suspected,
    );

    test('toJson writes every key, null included', () {
      expect(bare.toJson(), <String, Object?>{
        'restrictionId': 'wheat',
        'source': 'hidden',
        'certainty': 'likely',
        'tier': 'suspected',
        'matchedText': null,
        'waiterQuestion': null,
      });
    });

    test('tryFromJson(x.toJson()) round-trips through JSON text', () {
      for (final concern in [full, bare]) {
        // Act
        final result = Concern.tryFromJson(
          jsonDecode(jsonEncode(concern.toJson())) as Map<String, Object?>,
        );

        // Assert
        expect(result, equals(concern));
        expect(result?.hashCode, equals(concern.hashCode));
      }
    });

    test('tryFromJson returns null for a missing or unknown enum name', () {
      for (final key in ['restrictionId', 'source', 'certainty', 'tier']) {
        final missing = <String, Object?>{...full.toJson()}..remove(key);
        expect(Concern.tryFromJson(missing), isNull, reason: 'no $key');
        expect(
          Concern.tryFromJson(<String, Object?>{...full.toJson(), key: 'zzz'}),
          isNull,
          reason: 'unknown $key',
        );
        expect(
          Concern.tryFromJson(<String, Object?>{...full.toJson(), key: 1}),
          isNull,
          reason: 'non-string $key',
        );
      }
    });

    test('tryFromJson reads an absent, non-string or empty optional text as '
        'null and ignores unknown keys', () {
      for (final raw in <Object?>[null, 3, '']) {
        final result = Concern.tryFromJson(<String, Object?>{
          ...full.toJson(),
          'matchedText': raw,
          'waiterQuestion': raw,
          'extra': true,
        });
        expect(
          result,
          equals(
            const Concern(
              restrictionId: RestrictionId.sesame,
              source: ConcernSource.description,
              certainty: Certainty.stated,
              tier: EvidenceTier.stated,
            ),
          ),
          reason: '$raw',
        );
      }
    });

    test('== compares every field', () {
      expect(full, isNot(equals(bare)));
      expect(
        full,
        isNot(
          equals(
            const Concern(
              restrictionId: RestrictionId.sesame,
              source: ConcernSource.description,
              certainty: Certainty.stated,
              tier: EvidenceTier.stated,
              matchedText: 'טחינה',
            ),
          ),
        ),
      );
      expect(full.toString(), 'Concern(sesame, description, stated, stated)');
    });
  });

  group('ExtractedIngredient', () {
    const tahini = ExtractedIngredient(
      name: 'tahini',
      certainty: Certainty.stated,
      role: ComponentRole.sauce,
    );

    test('role defaults to unknown', () {
      expect(
        const ExtractedIngredient(
          name: 'bread',
          certainty: Certainty.likely,
        ).role,
        ComponentRole.unknown,
      );
    });

    test('tryFromJson(x.toJson()) round-trips through JSON text', () {
      // Act
      final written = tahini.toJson();
      final result = ExtractedIngredient.tryFromJson(
        jsonDecode(jsonEncode(written)) as Map<String, Object?>,
      );

      // Assert
      expect(written, <String, Object?>{
        'name': 'tahini',
        'certainty': 'stated',
        'role': 'sauce',
      });
      expect(result, equals(tahini));
      expect(result?.hashCode, equals(tahini.hashCode));
    });

    test('tryFromJson returns null for a missing or blank name', () {
      for (final raw in <Object?>[null, 3, '', '  ']) {
        expect(
          ExtractedIngredient.tryFromJson(<String, Object?>{
            ...tahini.toJson(),
            'name': raw,
          }),
          isNull,
          reason: '$raw',
        );
      }
    });

    test('tryFromJson returns null for a missing or unknown certainty', () {
      for (final raw in <Object?>[null, 'certain', 2]) {
        expect(
          ExtractedIngredient.tryFromJson(<String, Object?>{
            ...tahini.toJson(),
            'certainty': raw,
          }),
          isNull,
          reason: '$raw',
        );
      }
    });

    test('tryFromJson reads a missing or unknown role as unknown, so the '
        'ingredient is kept', () {
      for (final raw in <Object?>[null, 'topping', 5]) {
        expect(
          ExtractedIngredient.tryFromJson(<String, Object?>{
            ...tahini.toJson(),
            'role': raw,
          }),
          const ExtractedIngredient(
            name: 'tahini',
            certainty: Certainty.stated,
          ),
          reason: '$raw',
        );
      }
    });

    test('== compares every field', () {
      expect(
        tahini,
        isNot(
          equals(
            const ExtractedIngredient(
              name: 'tahini',
              certainty: Certainty.likely,
              role: ComponentRole.sauce,
            ),
          ),
        ),
      );
      expect(
        tahini,
        isNot(
          equals(
            const ExtractedIngredient(
              name: 'tahini',
              certainty: Certainty.stated,
              role: ComponentRole.side,
            ),
          ),
        ),
      );
      expect(tahini.toString(), 'ExtractedIngredient(tahini, stated, sauce)');
    });
  });
}
