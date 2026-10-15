// The allergen matrix model (Banto; ALG-16, related to #358): read
// tolerantly from `allergenMatrix` on GET /v1/venue-menus, absent or
// unreadable → none, unknown cells dropped one by one.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/allergen_matrix.dart';
import 'package:ketoclub/models/restriction.dart';

Map<String, Object?> _json({
  Object? source = 'restaurant',
  Object? validFrom = '2026-10-01',
  Object? validUntil = '2027-03-31',
  Object? rows,
}) => <String, Object?>{
  'source': source,
  'validFrom': validFrom,
  'validUntil': validUntil,
  'rows':
      rows ??
      <Object?>[
        <String, Object?>{
          'name': 'שקשוקה',
          'aliases': <Object?>['Shakshuka'],
          'allergens': <String, Object?>{
            'eggs': 'contains',
            'gluten': 'may_contain',
            'sesame': 'free',
          },
        },
      ],
};

void main() {
  group('AllergenMatrix.tryFrom', () {
    test('reads the wire form', () {
      // Act
      final matrix = AllergenMatrix.tryFrom(_json())!;

      // Assert
      expect(matrix.source, MatrixSource.restaurant);
      expect(matrix.validFrom, DateTime.utc(2026, 10));
      expect(matrix.validUntil, DateTime.utc(2027, 3, 31));
      final row = matrix.rows.single;
      expect(row.name, 'שקשוקה');
      expect(row.aliases, ['Shakshuka']);
      expect(row.names, ['שקשוקה', 'Shakshuka']);
      expect(row.cells, {
        RestrictionId.eggs: MatrixCell.contains,
        RestrictionId.gluten: MatrixCell.mayContain,
        RestrictionId.sesame: MatrixCell.free,
      });
    });

    test('round-trips through toJson', () {
      // Arrange
      final matrix = AllergenMatrix.tryFrom(_json())!;

      // Act
      final again = AllergenMatrix.tryFrom(matrix.toJson());

      // Assert
      expect(again, matrix);
      expect(again.hashCode, matrix.hashCode);
      expect(matrix.toJson()['validFrom'], '2026-10-01');
    });

    test('a null validUntil holds until replaced', () {
      // Act
      final matrix = AllergenMatrix.tryFrom(_json(validUntil: null))!;

      // Assert
      expect(matrix.validUntil, isNull);
      expect(matrix.toJson()['validUntil'], isNull);
      expect(matrix.holdsOn(DateTime.utc(2099)), isTrue);
    });

    final unreadable = <String, Object?>{
      'absent': null,
      'not an object': 'matrix',
      'an unknown source': _json(source: 'a friend'),
      'a missing validFrom': _json(validFrom: null),
      'a malformed validFrom': _json(validFrom: '1.10.2026'),
      'an impossible day': _json(validFrom: '2026-02-30'),
      'a malformed validUntil': _json(validUntil: 'soon'),
      'validUntil before validFrom': _json(validUntil: '2026-09-30'),
      'rows that are not a list': _json(rows: 'none'),
      'no readable row': _json(rows: <Object?>[<String, Object?>{}]),
      'no row at all': _json(rows: <Object?>[]),
    };
    for (final MapEntry(key: label, value: raw) in unreadable.entries) {
      test('$label reads as no matrix', () {
        expect(AllergenMatrix.tryFrom(raw), isNull);
      });
    }

    test('drops an unreadable row, cell or alias and keeps the rest', () {
      // Act
      final matrix = AllergenMatrix.tryFrom(
        _json(
          rows: <Object?>[
            'not a row',
            <String, Object?>{'name': '  ', 'allergens': <String, Object?>{}},
            <String, Object?>{
              'name': 'Salad',
              'aliases': <Object?>[7, '', 'סלט'],
              'allergens': <String, Object?>{
                'wheat': 'contains',
                'keto': 'free',
                'nonsense': 'contains',
                'eggs': 'yes',
                'milk': 'free',
              },
            },
            <String, Object?>{'name': 'Bread', 'allergens': 'none'},
          ],
        ),
      )!;

      // Assert: wheat and keto are no EU 14 column; "yes" is no value.
      expect(matrix.rows.map((row) => row.name), ['Salad', 'Bread']);
      expect(matrix.rows.first.aliases, ['סלט']);
      expect(matrix.rows.first.cells, {RestrictionId.milk: MatrixCell.free});
      expect(matrix.rows.last.cells, isEmpty);
    });
  });

  group('AllergenMatrix.holdsOn', () {
    final matrix = AllergenMatrix.tryFrom(_json())!;

    test('holds from its first through its last day, by UTC day', () {
      expect(matrix.holdsOn(DateTime.utc(2026, 9, 30, 23, 59)), isFalse);
      expect(matrix.holdsOn(DateTime.utc(2026, 10)), isTrue);
      expect(matrix.holdsOn(DateTime.utc(2027, 3, 31, 23, 59)), isTrue);
      expect(matrix.holdsOn(DateTime.utc(2027, 4)), isFalse);
    });
  });

  test('the columns are the EU 14, in the regulation order', () {
    expect(matrixColumns.map((id) => id.name), [
      'gluten',
      'crustaceans',
      'eggs',
      'fish',
      'peanuts',
      'soy',
      'milk',
      'treeNuts',
      'celery',
      'mustard',
      'sesame',
      'sulphites',
      'lupin',
      'molluscs',
    ]);
  });

  test('a cell reads by its wire spelling only', () {
    expect(MatrixCell.tryParse('may_contain'), MatrixCell.mayContain);
    expect(MatrixCell.tryParse('mayContain'), isNull);
    expect(MatrixCell.tryParse(null), isNull);
  });

  test('describes itself without its rows', () {
    final matrix = AllergenMatrix.tryFrom(_json())!;

    expect(matrix.toString(), 'AllergenMatrix(2026-10-01, 1 rows)');
    expect(matrix.rows.single.toString(), 'AllergenMatrixRow(שקשוקה, 3 cells)');
  });
}
