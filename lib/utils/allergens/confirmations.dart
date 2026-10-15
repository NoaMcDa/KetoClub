/// What the staff said, as evidence for the profile evaluator (Banto; the
/// Allergens epic, ALG-14, issue #356; architecture.md D27).
///
/// After a meal a person can record, from the Recent tab, what the staff
/// told them about a restriction in a dish ([DishConfirmation]). The next
/// time the menu opens, [Confirmations.apply] — called once from
/// `ProfileEvaluator.evaluate`, after the declarations step — moves each
/// concern it answers to [EvidenceTier.confirmed] or [EvidenceTier.denied]:
///
/// - **confirmed present** raises the concern to [Certainty.stated] (a
///   heads-up restriction's stays suspected: no menu states a dose, ALG-17),
///   and adds it where it was found when the evaluation no longer finds it;
/// - **confirmed absent** lowers it, and **never below
///   [Certainty.suspected]**: a strict entry's concern stays, so the dish
///   still reads "ask" (file 09: the app never tells an allergic person
///   something is absent; a kitchen's answer holds for one visit). A
///   flexible entry's concern is kept too, at suspected, where it moves
///   nothing, so the Why sheet can still say what the staff said.
///
/// The evidence is a list of [ConfirmationEvidence] so the same rule can
/// later read counts shared by other people ([ConfirmationEvidence.shared],
/// [ConfirmationEvidence.count]): a shared piece counts only from
/// [sharedConfirmationThreshold] people, a shared denial lowers one step
/// rather than straight to suspected, and the person's own answer always
/// outranks a shared one. Nothing builds shared evidence yet; there is no
/// network code here.
///
/// Device-only and pure: no golden, no Python twin (D26 C1). Never a
/// rating: evidence is per dish and per restriction, and nothing here sums
/// a venue into a number (D27).
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// How many people a shared count needs before it is evidence (file 10,
/// ALG-14 "Abuse").
const int sharedConfirmationThreshold = 3;

/// One piece of staff-confirmation evidence about one restriction in one
/// dish: the person's own answer, or (later) a count shared by others.
@immutable
final class ConfirmationEvidence {
  /// Creates a piece of evidence about [restrictionId].
  const new({
    required this.restrictionId,
    required this.polarity,
    required this.day,
    this.shared = false,
    this.count = 1,
    this.source,
    this.matchedText,
  });

  /// The person's own answer [confirmation] as evidence.
  // A named constructor still needs its class name (see `VerdictTone.lerp`).
  // ignore: unnecessary_type_name_in_constructor
  factory ConfirmationEvidence.fromLocal(DishConfirmation confirmation) =>
      ConfirmationEvidence(
        restrictionId: confirmation.restrictionId,
        polarity: confirmation.polarity,
        day: confirmation.day,
        source: confirmation.source,
        matchedText: confirmation.matchedText,
      );

  /// The restriction the evidence is about.
  final RestrictionId restrictionId;

  /// What the staff said.
  final ConfirmationPolarity polarity;

  /// The day of the answer; for a shared count, the last day.
  final DateTime day;

  /// Whether the evidence comes from other people's answers rather than
  /// this person's own.
  final bool shared;

  /// How many people gave the answer; 1 for the person's own.
  final int count;

  /// Where the concern asked about had been found, when known: where a
  /// confirmed restriction is shown if the evaluation no longer finds it.
  final ConcernSource? source;

  /// The menu's words the concern asked about had matched, when any.
  final String? matchedText;

  @override
  bool operator ==(Object other) =>
      other is ConfirmationEvidence &&
      other.restrictionId == restrictionId &&
      other.polarity == polarity &&
      other.day == day &&
      other.shared == shared &&
      other.count == count &&
      other.source == source &&
      other.matchedText == matchedText;

  @override
  int get hashCode => Object.hash(
    restrictionId,
    polarity,
    day,
    shared,
    count,
    source,
    matchedText,
  );

  @override
  String toString() =>
      'ConfirmationEvidence(${restrictionId.name}, ${polarity.name}, '
      '${confirmationDayKey(day)}${shared ? ', shared ×$count' : ''})';
}

/// Staff confirmations applied to a dish's concerns (ALG-14).
abstract final class Confirmations {
  /// The person's own answers about the dish [dishId] among [stored], as
  /// evidence, in their stored order.
  static List<ConfirmationEvidence> forDish(
    String dishId,
    List<DishConfirmation> stored,
  ) => <ConfirmationEvidence>[
    for (final confirmation in stored)
      if (confirmation.dishId == dishId)
        ConfirmationEvidence.fromLocal(confirmation),
  ];

  /// The key a concern and a piece of evidence are matched under: the
  /// restriction, and for the user's own restriction (ALG-17) also its
  /// words, as `ProfileEvaluator.concernKey` keys it.
  static String keyOf(RestrictionId id, String? matchedText) =>
      id == RestrictionId.custom
      ? '${id.name}:${AllergenMatcher.matchText(matchedText ?? '')}'
      : id.name;

  /// The piece of [evidence] that answers [concern], or null when none
  /// does: the person's own latest answer (present at a tie, the safer
  /// side), else, among shared counts of at least
  /// [sharedConfirmationThreshold] people, the latest present one, else
  /// the latest absent one.
  static ConfirmationEvidence? deciding(
    Concern concern,
    List<ConfirmationEvidence> evidence,
  ) =>
      _decidingFor(keyOf(concern.restrictionId, concern.matchedText), evidence);

  static ConfirmationEvidence? _decidingFor(
    String key,
    List<ConfirmationEvidence> evidence,
  ) {
    ConfirmationEvidence? own;
    ConfirmationEvidence? sharedPresent;
    ConfirmationEvidence? sharedAbsent;
    for (final piece in evidence) {
      if (keyOf(piece.restrictionId, piece.matchedText) != key) continue;
      if (!piece.shared) {
        if (own == null || _laterOrSafer(piece, own)) own = piece;
      } else if (piece.count >= sharedConfirmationThreshold) {
        if (piece.polarity == ConfirmationPolarity.present) {
          if (sharedPresent == null || piece.day.isAfter(sharedPresent.day)) {
            sharedPresent = piece;
          }
        } else if (sharedAbsent == null ||
            piece.day.isAfter(sharedAbsent.day)) {
          sharedAbsent = piece;
        }
      }
    }
    return own ?? sharedPresent ?? sharedAbsent;
  }

  /// Whether [candidate] should replace [kept] as the person's own
  /// deciding answer: a later day, or the same day and present.
  static bool _laterOrSafer(
    ConfirmationEvidence candidate,
    ConfirmationEvidence kept,
  ) {
    if (candidate.day.isAfter(kept.day)) return true;
    return candidate.day == kept.day &&
        candidate.polarity == ConfirmationPolarity.present &&
        kept.polarity == ConfirmationPolarity.absent;
  }

  /// [concern] as [piece] leaves it: present → [Certainty.stated] (a
  /// heads-up restriction's certainty unchanged) at
  /// [EvidenceTier.confirmed]; absent → [Certainty.suspected] for the
  /// person's own answer and one step lower for a shared count, never
  /// below suspected, at [EvidenceTier.denied]. Source, words and
  /// question are kept.
  static Concern adjust(Concern concern, ConfirmationEvidence piece) {
    final Certainty certainty;
    final EvidenceTier tier;
    if (piece.polarity == ConfirmationPolarity.present) {
      certainty = headsUpRestrictions.contains(concern.restrictionId)
          ? concern.certainty
          : Certainty.stated;
      tier = EvidenceTier.confirmed;
    } else {
      certainty = piece.shared
          ? _oneStepLower(concern.certainty)
          : Certainty.suspected;
      tier = EvidenceTier.denied;
    }
    return Concern(
      restrictionId: concern.restrictionId,
      source: concern.source,
      certainty: certainty,
      tier: tier,
      matchedText: concern.matchedText,
      waiterQuestion: concern.waiterQuestion,
    );
  }

  /// [certainty] one step lower, never below [Certainty.suspected].
  static Certainty _oneStepLower(Certainty certainty) => switch (certainty) {
    Certainty.stated => Certainty.likely,
    Certainty.likely || Certainty.suspected => Certainty.suspected,
  };

  /// [items] — a dish's evidence, each holding a concern ([concernOf]) —
  /// with every concern [evidence] answers adjusted ([adjust], rebuilt by
  /// [withConcern]), followed by one item ([added]) per restriction the
  /// staff confirmed present that no item holds any more, placed where it
  /// had been found ([ConfirmationEvidence.source]; a piece that does not
  /// know is skipped) and kept only when [applies] says the profile holds
  /// it. Returns the items and the pieces that decided something, for the
  /// Why sheet. With no [evidence], [items] are returned as they are.
  static ({List<T> items, List<ConfirmationEvidence> applied}) apply<T>(
    List<T> items,
    List<ConfirmationEvidence> evidence, {
    required Concern Function(T item) concernOf,
    required T Function(T item, Concern concern) withConcern,
    required T Function(Concern concern) added,
    required bool Function(Concern concern) applies,
  }) {
    if (evidence.isEmpty) {
      return (items: items, applied: const <ConfirmationEvidence>[]);
    }
    final applied = <ConfirmationEvidence>[];
    void note(ConfirmationEvidence piece) {
      if (!applied.contains(piece)) applied.add(piece);
    }

    final seen = <String>{};
    final result = <T>[];
    for (final item in items) {
      final concern = concernOf(item);
      final key = keyOf(concern.restrictionId, concern.matchedText);
      seen.add(key);
      final piece = _decidingFor(key, evidence);
      if (piece == null) {
        result.add(item);
        continue;
      }
      note(piece);
      result.add(withConcern(item, adjust(concern, piece)));
    }
    for (final piece in evidence) {
      final key = keyOf(piece.restrictionId, piece.matchedText);
      if (!seen.add(key)) continue;
      final decided = _decidingFor(key, evidence);
      final source = decided?.source;
      if (decided == null ||
          decided.polarity != ConfirmationPolarity.present ||
          source == null) {
        continue;
      }
      final concern = Concern(
        restrictionId: decided.restrictionId,
        source: source,
        certainty: headsUpRestrictions.contains(decided.restrictionId)
            ? Certainty.suspected
            : Certainty.stated,
        tier: EvidenceTier.confirmed,
        matchedText: decided.matchedText,
      );
      if (!applies(concern)) continue;
      note(decided);
      result.add(added(concern));
    }
    return (
      items: result,
      applied: List<ConfirmationEvidence>.unmodifiable(applied),
    );
  }
}
