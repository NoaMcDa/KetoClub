/// What a dish may hold for a restriction, and the ingredients a model read
/// in it (Banto; the Allergens epic, ALG-03, ALG-04 and ALG-06, issues #345
/// and #346; architecture.md D26, W2-0).
///
/// These are the wire types only: nothing produces a [Concern] or an
/// [ExtractedIngredient] yet. A [Concern] names a restriction for every
/// taxonomy id found, whatever anyone's profile (D26 C1); the device
/// filters by the profile.
///
/// Every enum is matched by `name`, never by ordinal, so reordering or
/// adding a value cannot re-map cached data. A reader that meets a name it
/// does not know returns null, and the list that holds the entry drops it
/// (architecture.md §9.4), with one exception: an unknown or missing
/// [ExtractedIngredient.role] reads as [ComponentRole.unknown], so an
/// ingredient is never lost over its role.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/restriction.dart';

/// The value of [E] whose name equals [wire], or null when [wire] is not a
/// string or no value has that name.
E? _enumByName<E extends Enum>(List<E> values, Object? wire) {
  if (wire is! String) return null;
  for (final value in values) {
    if (value.name == wire) return value;
  }
  return null;
}

/// [raw] when it is a non-empty string, else null.
String? _optionalText(Object? raw) =>
    raw is String && raw.isNotEmpty ? raw : null;

/// Where on the dish a [Concern] was found.
enum ConcernSource {
  /// In the dish's name.
  name,

  /// In the dish's description.
  description,

  /// In one of the dish's option values ("choice of side: bread").
  option,

  /// A hidden source the text implies ("soy sauce" → wheat).
  hidden,

  /// In the model's ingredient extraction, not in the dish text.
  model,

  /// Not in the dish at all: in the kitchen the menu reveals (ALG-07,
  /// `utils/allergens/kitchen_reach.dart`). Made on the device only, so
  /// it is written nowhere unless a kitchen concern is; its
  /// [Concern.matchedText] holds the kitchen signal kind's name ("fryer"),
  /// not menu text.
  kitchen;

  /// The source whose [name] equals [wire], or null when none does.
  static ConcernSource? tryParse(String wire) =>
      _enumByName(ConcernSource.values, wire);
}

/// How sure a finding is that a restriction is present.
///
/// The same three names, in the same order and with the same meaning, as
/// the allergen vocabulary's `TriggerCertainty`
/// (`lib/utils/allergens/vocabulary_types.dart`), which a model may not
/// import (architecture.md §5). Convert a trigger's certainty by name,
/// `Certainty.tryParse(trigger.certainty.name)`; a test pins the two
/// enums' names equal.
enum Certainty {
  /// The words are in the dish text ("sesame", "טחינה").
  stated,

  /// A source that usually carries it.
  likely,

  /// A source that sometimes carries it, or a guess.
  suspected;

  /// The certainty whose [name] equals [wire], or null when none does.
  static Certainty? tryParse(String wire) =>
      _enumByName(Certainty.values, wire);
}

/// How a [Concern] is known, strongest first (ALG-06).
enum EvidenceTier {
  /// The platform or the restaurant said so (ALG-09, ALG-16).
  declared,

  /// The words are in the dish text.
  stated,

  /// A dish-name rule: "schnitzel" → wheat.
  inferred,

  /// A hidden-source rule or the model's guess.
  suspected,

  /// A person asked the kitchen, and it is there (ALG-14).
  confirmed,

  /// A person asked the kitchen, and it is not there (ALG-14).
  denied;

  /// The tier whose [name] equals [wire], or null when none does.
  static EvidenceTier? tryParse(String wire) =>
      _enumByName(EvidenceTier.values, wire);
}

/// Which part of a dish an [ExtractedIngredient] belongs to (ALG-03).
///
/// A side, sauce, garnish or option is removable; a base or a protein is
/// not.
enum ComponentRole {
  /// The dish's base: the pasta, the bread, the rice.
  base,

  /// The dish's protein.
  protein,

  /// A side served with it.
  side,

  /// A sauce or dressing.
  sauce,

  /// A garnish or topping.
  garnish,

  /// A chosen option.
  option,

  /// The role could not be told.
  unknown;

  /// The role whose [name] equals [wire], or null when none does.
  static ComponentRole? tryParse(String wire) =>
      _enumByName(ComponentRole.values, wire);
}

/// One restriction a dish may hold, with where and how it was found
/// (ALG-03, ALG-04, ALG-06).
///
/// Immutable value type; round-trips through [toJson]/[tryFromJson].
@immutable
final class Concern {
  /// Creates a concern for [restrictionId].
  const new({
    required this.restrictionId,
    required this.source,
    required this.certainty,
    required this.tier,
    this.matchedText,
    this.waiterQuestion,
  });

  /// Reads a concern written by [toJson].
  ///
  /// Returns null, and never throws, when `restrictionId`, `source`,
  /// `certainty` or `tier` is missing or names no known value. An absent,
  /// non-string or empty `matchedText`/`waiterQuestion` reads as null.
  static Concern? tryFromJson(Map<String, Object?> json) {
    final restrictionId = _enumByName(
      RestrictionId.values,
      json['restrictionId'],
    );
    final source = _enumByName(ConcernSource.values, json['source']);
    final certainty = _enumByName(Certainty.values, json['certainty']);
    final tier = _enumByName(EvidenceTier.values, json['tier']);
    if (restrictionId == null ||
        source == null ||
        certainty == null ||
        tier == null) {
      return null;
    }
    return Concern(
      restrictionId: restrictionId,
      source: source,
      certainty: certainty,
      tier: tier,
      matchedText: _optionalText(json['matchedText']),
      waiterQuestion: _optionalText(json['waiterQuestion']),
    );
  }

  /// The restriction this concern is about.
  final RestrictionId restrictionId;

  /// Where on the dish it was found.
  final ConcernSource source;

  /// How sure the finding is.
  final Certainty certainty;

  /// How it is known (ALG-06).
  final EvidenceTier tier;

  /// The exact text the finding matched, when there is one ("tahini").
  final String? matchedText;

  /// A question for the waiter in the menu's own language (architecture.md
  /// §12), when one would settle it.
  final String? waiterQuestion;

  /// Writes a form [tryFromJson] can read back. Every key is written,
  /// null included.
  Map<String, Object?> toJson() => <String, Object?>{
    'restrictionId': restrictionId.name,
    'source': source.name,
    'certainty': certainty.name,
    'tier': tier.name,
    'matchedText': matchedText,
    'waiterQuestion': waiterQuestion,
  };

  @override
  bool operator ==(Object other) =>
      other is Concern &&
      other.restrictionId == restrictionId &&
      other.source == source &&
      other.certainty == certainty &&
      other.tier == tier &&
      other.matchedText == matchedText &&
      other.waiterQuestion == waiterQuestion;

  @override
  int get hashCode => Object.hash(
    restrictionId,
    source,
    certainty,
    tier,
    matchedText,
    waiterQuestion,
  );

  @override
  String toString() =>
      'Concern(${restrictionId.name}, ${source.name}, '
      '${certainty.name}, ${tier.name})';
}

/// One ingredient a model read or inferred in a dish, independently of any
/// profile (ALG-03, D26 C1).
///
/// Immutable value type; round-trips through [toJson]/[tryFromJson].
@immutable
final class ExtractedIngredient {
  /// Creates an ingredient named [name].
  const new({
    required this.name,
    required this.certainty,
    this.role = ComponentRole.unknown,
  });

  /// Reads an ingredient written by [toJson].
  ///
  /// Returns null, and never throws, when `name` is missing or blank or
  /// `certainty` names no known value. An absent or unknown `role` reads
  /// as [ComponentRole.unknown] rather than dropping the ingredient.
  static ExtractedIngredient? tryFromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final certainty = _enumByName(Certainty.values, json['certainty']);
    if (certainty == null) return null;
    final role =
        _enumByName(ComponentRole.values, json['role']) ??
        ComponentRole.unknown;
    return ExtractedIngredient(name: name, certainty: certainty, role: role);
  }

  /// The ingredient as the model named it. Never blank.
  final String name;

  /// How sure the model is that the dish holds it.
  final Certainty certainty;

  /// Which part of the dish it belongs to.
  final ComponentRole role;

  /// Writes a form [tryFromJson] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'certainty': certainty.name,
    'role': role.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ExtractedIngredient &&
      other.name == name &&
      other.certainty == certainty &&
      other.role == role;

  @override
  int get hashCode => Object.hash(name, certainty, role);

  @override
  String toString() =>
      'ExtractedIngredient($name, ${certainty.name}, ${role.name})';
}
