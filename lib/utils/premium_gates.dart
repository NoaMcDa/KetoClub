import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';

/// How many restrictions besides keto a profile holds on the free plan
/// (Banto, ALG-18): file 07's "one restriction". Keto is KetoClub's own
/// baseline and is never counted.
const int freeRestrictionCount = 1;

/// How many menu scans — photographs, PDFs and pasted text — the free plan
/// reads a month (ALG-18). File 07 leaves the number open ("up to X scans a
/// month"); five is the default the issue names until the owner picks one.
const int freeScansPerMonth = 5;

/// What Premium adds (ALG-18, file 07): the four things the free plan
/// gates, and nothing else. A test pins this list, so a new gate is a
/// deliberate change; what is never gated (the chef card, the helper
/// copy, confirmations, waiter questions, the Why sheet and every
/// restriction already saved) has no member here and cannot be named.
enum PremiumFeature {
  /// More than [freeRestrictionCount] restriction in a profile ("the
  /// combined profile").
  restrictions,

  /// Profiles for other people, and reading a menu for several at once.
  groupProfiles,

  /// Trip mode: picking a destination.
  tripMode,

  /// More than [freeScansPerMonth] scans a month.
  scans,
}

/// Who is asking, for the gate decisions in [PremiumGates] (ALG-18).
///
/// Only a Banto build that sells Premium — a phone with a store — and has
/// no active subscription is limited. The web build sells nothing and stays
/// free (its quota is the backend's rate limit), and a KetoClub build is
/// never gated at all.
final class PremiumAccess {
  /// Creates the access for a build with [bantoMode] that [sellsPremium]
  /// and, when it does, whether [premium] is active.
  const new({
    required this.bantoMode,
    required this.sellsPremium,
    required this.premium,
  });

  /// No limit at all: a KetoClub build, the web build or a test.
  static const PremiumAccess unlimited = PremiumAccess(
    bantoMode: false,
    sellsPremium: false,
    premium: false,
  );

  /// Whether this build shows Banto surfaces (D26's convention).
  final bool bantoMode;

  /// Whether this build sells Premium (false on web).
  final bool sellsPremium;

  /// Whether Premium is active.
  final bool premium;

  /// Whether the free plan's limits apply.
  bool get limited => bantoMode && sellsPremium && !premium;
}

/// The free plan's gates (Banto, ALG-18, issue #360), as pure decisions.
///
/// **Only adding is ever gated.** Each method answers whether one new
/// thing — a restriction, a person, a checked person, a destination, a
/// scan — may be added; none says anything about what is already saved. A
/// person whose Premium lapsed keeps every saved restriction, person and
/// trip, and every one of them is still evaluated on every menu: gating
/// what is already in a profile would be gating safety, which the research
/// names as the fastest way to lose trust (file 05, complaint 4).
abstract final class PremiumGates {
  /// Whether adding [adding] to [profile] needs Premium: only when it would
  /// be a new restriction besides keto while [profile] already holds
  /// [freeRestrictionCount] of them. Adding keto, re-adding an entry it
  /// holds, or another word to the user's own entry it already holds
  /// ([RestrictionId.custom]) adds no restriction and is never gated.
  static bool locksAddingRestriction(
    PremiumAccess access, {
    required DietaryProfile profile,
    required RestrictionId adding,
  }) {
    if (!access.limited) return false;
    if (adding == RestrictionId.keto || profile.contains(adding)) return false;
    return countedRestrictions(profile) >= freeRestrictionCount;
  }

  /// Whether choosing [adding] on the first-run onboarding, with [chosen]
  /// already picked, needs Premium: the onboarding's form of
  /// [locksAddingRestriction].
  static bool locksChoosing(
    PremiumAccess access, {
    required List<RestrictionId> chosen,
    required RestrictionId adding,
  }) {
    if (!access.limited) return false;
    if (adding == RestrictionId.keto || chosen.contains(adding)) return false;
    final counted = chosen.where((id) => id != RestrictionId.keto).length;
    return counted >= freeRestrictionCount;
  }

  /// The restrictions of [profile] the free plan counts: every entry but
  /// keto.
  static int countedRestrictions(DietaryProfile profile) => profile.entries
      .where((entry) => entry.restrictionId != RestrictionId.keto)
      .length;

  /// Whether adding another person's profile (by hand or by import) needs
  /// Premium.
  static bool locksAddingPerson(PremiumAccess access) => access.limited;

  /// Whether reading a menu for [next] instead of [current] needs Premium:
  /// only when [next] is several people and checks one [current] did not.
  /// Keeping or narrowing a choice already saved is never gated.
  static bool locksCheckingPeople(
    PremiumAccess access, {
    required Iterable<String> current,
    required Iterable<String> next,
  }) {
    if (!access.limited) return false;
    final chosen = next.toSet();
    if (chosen.length < 2) return false;
    return !current.toSet().containsAll(chosen);
  }

  /// Whether picking a trip destination needs Premium. Turning a trip off,
  /// and the briefing of a trip already on, are never gated.
  static bool locksPickingDestination(PremiumAccess access) => access.limited;

  /// Whether one more scan, after [scansThisMonth] this month, needs
  /// Premium.
  static bool locksScan(PremiumAccess access, {required int scansThisMonth}) =>
      access.limited && scansThisMonth >= freeScansPerMonth;

  /// How many free scans are left this month after [scansThisMonth], never
  /// below zero.
  static int freeScansLeft(int scansThisMonth) =>
      scansThisMonth >= freeScansPerMonth
      ? 0
      : freeScansPerMonth - scansThisMonth;
}

/// The month [now] falls in, as `YYYY-MM` in UTC: the key the monthly scan
/// counter is kept under (`AppSettings.scanMonth`). UTC, so the same
/// instant is the same month on every device and in every test.
String scanMonthKey(DateTime now) {
  final utc = now.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  return '${utc.year}-$month';
}
