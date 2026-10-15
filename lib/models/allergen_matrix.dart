/// A restaurant's allergen matrix for one venue (Banto, ALG-16, related to
/// #358; architecture.md D26).
///
/// What the restaurant itself says about its dishes' allergens: one row per
/// dish by printed name (and the other names it is printed under), one
/// cell per EU 14 allergen ([matrixColumns]), each `contains`,
/// `may_contain` or `free`; a blank cell is absent. The maintainer enters
/// it on the backend (`backend/tools/allergen_matrix.py`; the format is in
/// `backend/README.md`) and the backend's venue-menu route answers the
/// one that holds that day as `allergenMatrix`, beside the menu.
///
/// Read tolerantly, as every Banto wire field is (D26 C3): an absent or
/// malformed matrix is no matrix, an unknown column or value drops that
/// cell only (no evidence, the conservative direction), and a row with no
/// name is dropped. The device never sends it anywhere; matching a row to
/// a dish is `utils/allergens/allergen_matrix.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/restriction.dart';

/// One allergen cell of a matrix row.
enum MatrixCell {
  /// The restaurant says the dish contains it.
  contains('contains'),

  /// The restaurant says the dish may contain it (cross-contact).
  mayContain('may_contain'),

  /// The restaurant says the dish is free of it.
  free('free');

  new(this.wire);

  /// The value as the matrix writes it.
  final String wire;

  /// The cell whose [wire] is [raw], or null for anything else.
  static MatrixCell? tryParse(Object? raw) {
    for (final cell in values) {
      if (cell.wire == raw) return cell;
    }
    return null;
  }
}

/// Where the restaurant's own information was read.
enum MatrixSource {
  /// Sent by the restaurant.
  restaurant,

  /// Printed or posted at the venue.
  printed,

  /// Published on the restaurant's website.
  website,
}

/// The EU 14 allergens a matrix has a column for, in the regulation's
/// order, by taxonomy id. "Cereals containing gluten" is
/// [RestrictionId.gluten] (the celiac entry), never [RestrictionId.wheat].
const List<RestrictionId> matrixColumns = <RestrictionId>[
  RestrictionId.gluten,
  RestrictionId.crustaceans,
  RestrictionId.eggs,
  RestrictionId.fish,
  RestrictionId.peanuts,
  RestrictionId.soy,
  RestrictionId.milk,
  RestrictionId.treeNuts,
  RestrictionId.celery,
  RestrictionId.mustard,
  RestrictionId.sesame,
  RestrictionId.sulphites,
  RestrictionId.lupin,
  RestrictionId.molluscs,
];

/// [raw] as a calendar day written `YYYY-MM-DD`, or null.
DateTime? _day(Object? raw) {
  if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  final day = DateTime.utc(parsed.year, parsed.month, parsed.day);
  // DateTime.parse rolls 2026-02-30 over to March; a matrix may not.
  return _dayText(day) == raw ? day : null;
}

/// [day] written `YYYY-MM-DD`.
String _dayText(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// One dish of a matrix.
@immutable
final class AllergenMatrixRow {
  /// Creates the row for the dish printed [name].
  const new({
    required this.name,
    this.aliases = const <String>[],
    this.cells = const <RestrictionId, MatrixCell>{},
  });

  /// Reads one row, or null when it has no name. Unknown columns and
  /// values are dropped cell by cell; a non-string alias is dropped.
  static AllergenMatrixRow? tryFrom(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final rawAliases = json['aliases'];
    final rawCells = json['allergens'];
    return AllergenMatrixRow(
      name: name,
      aliases: List<String>.unmodifiable(<String>[
        if (rawAliases is List<Object?>)
          for (final alias in rawAliases)
            if (alias is String && alias.trim().isNotEmpty) alias,
      ]),
      cells: Map<RestrictionId, MatrixCell>.unmodifiable(
        <RestrictionId, MatrixCell>{
          if (rawCells is Map<String, Object?>)
            for (final MapEntry(:key, :value) in rawCells.entries)
              if (RestrictionId.tryParse(key) case final id?
                  when matrixColumns.contains(id))
                id: ?MatrixCell.tryParse(value),
        },
      ),
    );
  }

  /// The dish's name as the matrix prints it.
  final String name;

  /// The other names the dish is printed under (its English name on a
  /// Hebrew menu, say), matched exactly like [name].
  final List<String> aliases;

  /// Each allergen the row has a non-blank cell for.
  final Map<RestrictionId, MatrixCell> cells;

  /// [name] then [aliases].
  List<String> get names => <String>[name, ...aliases];

  /// The wire form [tryFrom] reads back.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'aliases': aliases,
    'allergens': <String, Object?>{
      for (final MapEntry(:key, :value) in cells.entries) key.name: value.wire,
    },
  };

  @override
  bool operator ==(Object other) =>
      other is AllergenMatrixRow &&
      other.name == name &&
      listEquals(other.aliases, aliases) &&
      mapEquals(other.cells, cells);

  @override
  int get hashCode => Object.hash(
    name,
    Object.hashAll(aliases),
    Object.hashAllUnordered(<Object>[
      for (final MapEntry(:key, :value) in cells.entries) (key, value),
    ]),
  );

  @override
  String toString() => 'AllergenMatrixRow($name, ${cells.length} cells)';
}

/// A restaurant's allergen matrix for one venue (ALG-16).
@immutable
final class AllergenMatrix {
  /// Creates a matrix valid from [validFrom].
  const new({
    required this.source,
    required this.validFrom,
    required this.rows,
    this.validUntil,
  });

  /// Reads `allergenMatrix` as the venue-menu route (and the menu cache)
  /// writes it, or null when it is absent or unreadable: an unknown
  /// source, a missing or malformed date, a `validUntil` before
  /// `validFrom`, or no readable row. Never throws.
  static AllergenMatrix? tryFrom(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final source = switch (json['source']) {
      final String wire => MatrixSource.values.asNameMap()[wire],
      _ => null,
    };
    final validFrom = _day(json['validFrom']);
    final rawUntil = json['validUntil'];
    final validUntil = _day(rawUntil);
    final rawRows = json['rows'];
    if (source == null ||
        validFrom == null ||
        (rawUntil != null && validUntil == null) ||
        (validUntil != null && validUntil.isBefore(validFrom)) ||
        rawRows is! List<Object?>) {
      return null;
    }
    final rows = <AllergenMatrixRow>[
      for (final raw in rawRows) ?AllergenMatrixRow.tryFrom(raw),
    ];
    if (rows.isEmpty) return null;
    return AllergenMatrix(
      source: source,
      validFrom: validFrom,
      validUntil: validUntil,
      rows: List<AllergenMatrixRow>.unmodifiable(rows),
    );
  }

  /// Where the restaurant's information was read.
  final MatrixSource source;

  /// The first day it holds, at midnight UTC: the date the notice shows.
  final DateTime validFrom;

  /// The last day it holds, at midnight UTC, or null for "until replaced".
  final DateTime? validUntil;

  /// One per dish, in the matrix's order.
  final List<AllergenMatrixRow> rows;

  /// Whether the matrix holds on the calendar day of [moment] (read in
  /// UTC, as the backend chooses it).
  bool holdsOn(DateTime moment) {
    final utc = moment.toUtc();
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    final until = validUntil;
    return !day.isBefore(validFrom) && (until == null || !day.isAfter(until));
  }

  /// The wire form [tryFrom] reads back.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': source.name,
    'validFrom': _dayText(validFrom),
    'validUntil': validUntil == null ? null : _dayText(validUntil!),
    'rows': <Object?>[for (final row in rows) row.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is AllergenMatrix &&
      other.source == source &&
      other.validFrom == validFrom &&
      other.validUntil == validUntil &&
      listEquals(other.rows, rows);

  @override
  int get hashCode =>
      Object.hash(source, validFrom, validUntil, Object.hashAll(rows));

  @override
  String toString() =>
      'AllergenMatrix(${_dayText(validFrom)}, ${rows.length} rows)';
}
