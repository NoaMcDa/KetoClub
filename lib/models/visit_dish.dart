/// What a strict visit keeps of one dish, so the post-meal prompt can ask
/// about it after the menu's cached copy has gone (Banto; the Allergens
/// epic, ALG-14, issue #411; architecture.md D26).
///
/// The minimum that lets the prompt work: the dish's id (the key every
/// answer and note is stored under), its name, which strict restrictions
/// the profile had a concern about in it and whether it carried a change to
/// ask for. Never a description, a price or the dish's verdict.
///
/// Part of the visit history (D23): it is written to the device and leaves
/// it through nothing (D26 C1). Every reader is tolerant: a malformed
/// record reads as null and the list holding it drops it.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';

/// [raw] when it is a non-empty string, else null.
String? _optionalText(Object? raw) =>
    raw is String && raw.isNotEmpty ? raw : null;

/// One strict restriction a profile had a concern about in a dish.
@immutable
final class VisitConcern {
  /// Creates the concern for [restrictionId].
  const new({required this.restrictionId, this.source, this.matchedText});

  /// Reads a concern written by [toJson], or null, never throwing, when
  /// the restriction is missing or unknown. An unknown source reads as null.
  static VisitConcern? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final rawId = json['r'];
    final id = rawId is String ? RestrictionId.tryParse(rawId) : null;
    if (id == null) return null;
    final rawSource = json['s'];
    return VisitConcern(
      restrictionId: id,
      source: rawSource is String ? ConcernSource.tryParse(rawSource) : null,
      matchedText: _optionalText(json['t']),
    );
  }

  /// The restriction the concern is about.
  final RestrictionId restrictionId;

  /// Where on the dish it was found, when known.
  final ConcernSource? source;

  /// The menu's words the concern matched; kept only for the user's own
  /// restriction ([RestrictionId.custom]), whose answers are keyed by them.
  final String? matchedText;

  /// Writes a form [tryFromJson] can read back; a null field is left out.
  Map<String, Object?> toJson() => <String, Object?>{
    'r': restrictionId.name,
    's': ?source?.name,
    't': ?matchedText,
  };

  @override
  bool operator ==(Object other) =>
      other is VisitConcern &&
      other.restrictionId == restrictionId &&
      other.source == source &&
      other.matchedText == matchedText;

  @override
  int get hashCode => Object.hash(restrictionId, source, matchedText);

  @override
  String toString() => 'VisitConcern(${restrictionId.name})';
}

/// One dish of a strict visit: see the library comment.
@immutable
final class VisitDish {
  /// Creates the record of the dish [dishId] called [name].
  const new({
    required this.dishId,
    required this.name,
    required this.concerns,
    this.hasChange = false,
  });

  /// Reads a dish written by [toJson], or null, never throwing, when the
  /// id or the name is missing or there is no readable concern.
  static VisitDish? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = _optionalText(json['id']);
    final name = _optionalText(json['name']);
    final rawConcerns = json['concerns'];
    if (id == null || name == null || rawConcerns is! List<Object?>) {
      return null;
    }
    final concerns = <VisitConcern>[];
    for (final raw in rawConcerns) {
      final concern = VisitConcern.tryFromJson(raw);
      if (concern != null && !concerns.contains(concern)) {
        concerns.add(concern);
      }
    }
    if (concerns.isEmpty) return null;
    return VisitDish(
      dishId: id,
      name: name,
      concerns: List<VisitConcern>.unmodifiable(concerns),
      hasChange: json['change'] == true,
    );
  }

  /// The dish's id in the venue's menu: what answers and notes are keyed by.
  final String dishId;

  /// The dish's name as the menu printed it.
  final String name;

  /// The strict restrictions the profile had a concern about, one question
  /// each; never empty for a record read back.
  final List<VisitConcern> concerns;

  /// Whether the evaluation asked the kitchen for a change on this dish.
  final bool hasChange;

  /// Writes a form [tryFromJson] can read back; `change` only when true.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': dishId,
    'name': name,
    'concerns': <Object?>[for (final concern in concerns) concern.toJson()],
    if (hasChange) 'change': true,
  };

  @override
  bool operator ==(Object other) =>
      other is VisitDish &&
      other.dishId == dishId &&
      other.name == name &&
      other.hasChange == hasChange &&
      listEquals(other.concerns, concerns);

  @override
  int get hashCode =>
      Object.hash(dishId, name, hasChange, Object.hashAll(concerns));

  @override
  String toString() => 'VisitDish($dishId, ${concerns.length} concerns)';
}
