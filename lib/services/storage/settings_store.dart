/// Why these implementations catch `Exception` rather than naming
/// `PlatformException` and `MissingPluginException`: those types live in
/// `package:flutter/services.dart`, and `services/` may import nothing from
/// Flutter beyond `foundation.dart` (architecture.md §5, enforced by
/// `test/architecture/import_rules_test.dart`). Both implement `Exception`,
/// and each method below promises never to throw across its boundary, so the
/// broad clause states the contract rather than widening it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marks "leave this field unchanged" in [AppSettings.copyWith], distinct
/// from any real value the field can hold, including `null`. There is no
/// public way to obtain this object, so a caller can never pass it by
/// accident.
const Object _unset = Object();

/// The app-level appearance choice (issue #58), kept free of
/// `package:flutter/material.dart`'s `ThemeMode` so `services/` never
/// imports it (architecture.md §5) — `state/` maps this to `ThemeMode` for
/// `MaterialApp.themeMode`.
enum AppThemeMode {
  /// Follows the platform brightness.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark;

  /// The mode whose [name] equals [wire], or null when none does.
  ///
  /// Matches by string, never by ordinal, so reordering this enum cannot
  /// silently re-map cached data.
  static AppThemeMode? tryParse(String wire) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == wire) return mode;
    }
    return null;
  }
}

/// The two surfaces that nudge an empty profile (Banto, issue #421), each
/// dismissed on its own.
enum ProfileNudgeSurface {
  /// The menu screen, above the dishes.
  menu,

  /// The Discovery list.
  discovery,
}

/// The user's on-device preferences (architecture.md §6.4): UI language,
/// filter default, AI-estimation consent, the last venue opened, the
/// appearance (issue #58), the net-carb limit (issue #57), the
/// last-used filter (issue #55), the three "Your keto rules"
/// toggles (issue #56), whether the first-launch AI disclosure
/// banner has been seen (D16, issue #167), the restriction profile
/// (Banto, ALG-02a, issue #344), whether the first-run restriction
/// onboarding has been seen (ALG-02b), the other people's profiles and
/// which of them a menu is read for (ALG-12, issue #354), trip mode's
/// destination (ALG-13, issue #355) and the month's scan count the free
/// plan reads (ALG-18, issue #360), and which of the two empty-profile
/// notices the user dismissed (issue #421).
@immutable
final class AppSettings {
  /// Creates settings. Every field defaults to the "nothing set yet"
  /// value a virgin store should read back.
  ///
  /// [estimationConsentGiven] defaults to true (D16, issue #167): AI
  /// analysis is on by default on a fresh install, and the
  /// consent-disclosure banner (`lib/widgets/consent_disclosure_banner`)
  /// shown once on Explore is what the user sees to acknowledge it. A
  /// stored `false` still stays `false` —
  /// [tryFrom]'s round-trip pins that migration behaviour so an install
  /// that already refused before D16 keeps its refusal.
  const new({
    this.languageTag,
    this.filter = MenuFilter.all,
    this.estimationConsentGiven = true,
    this.lastVenue,
    this.themeMode = AppThemeMode.system,
    this.netCarbLimitGrams = defaultNetCarbLimitGrams,
    this.seedOilFree = false,
    this.dairyFree = false,
    this.carnivoreOnly = false,
    this.lastFilter,
    this.disclosureSeen = false,
    this.profile = DietaryProfile.empty,
    this.onboardingSeen = false,
    this.primaryProfileName = '',
    this.otherProfiles = const <NamedProfile>[],
    this.activeProfileIds = defaultActiveProfileIds,
    this.tripDestination,
    this.disclosureCopyVersion = 0,
    this.helperToolSeen = false,
    this.scanMonth = '',
    this.scanCount = 0,
    this.shareConfirmations = false,
    this.menuNudgeDismissed = false,
    this.discoveryNudgeDismissed = false,
  });

  /// The profiles a menu is read for until the user combines others: the
  /// device owner's own.
  static const List<String> defaultActiveProfileIds = <String>[
    NamedProfile.primaryId,
  ];

  /// Reads settings written by [toJson].
  ///
  /// Returns null for any shape mismatch, including a malformed
  /// [lastVenue] or an unknown [filter] name, and never throws. [themeMode]
  /// is the one exception (issue #58): it was added after installs already
  /// existed without it, so a missing or unrecognised value decodes to
  /// [AppThemeMode.system] rather than invalidating the whole record —
  /// unlike [filter], whose own unknown value already fails this way for
  /// data written before that field existed too.
  ///
  /// [netCarbLimitGrams] (issue #57) follows [themeMode]'s rule for the
  /// same reason: a missing or non-integer value decodes to
  /// [defaultNetCarbLimitGrams]. An integer outside
  /// [minNetCarbLimitGrams]..[maxNetCarbLimitGrams] is clamped into that
  /// range rather than rejected, so a hand-edited or future value still
  /// lands on the nearest limit the stepper can show.
  ///
  /// [seedOilFree], [dairyFree] and [carnivoreOnly] (issue #56) follow
  /// the same rule: each was added after installs already existed, so a
  /// missing or non-boolean value reads as false (the toggle off) rather
  /// than invalidating the record.
  ///
  /// [lastFilter] (issue #55) follows the same "added later" rule as
  /// [themeMode] and [netCarbLimitGrams]: a missing key, or one whose
  /// value [MenuFilter.tryParse] does not recognise, decodes to null —
  /// "no last-used filter yet" — rather than invalidating the record.
  ///
  /// [profile] (issue #344) follows the same rule: a missing key reads as
  /// [DietaryProfile.empty], and [DietaryProfile.tryFrom] drops what it
  /// cannot read rather than invalidating the record.
  ///
  /// The group profiles (ALG-12, issue #354) follow it too. An install
  /// from before them has only [profile], which reads as the one primary
  /// profile, named "Me" by the UI: that is the whole migration. A
  /// non-string [primaryProfileName] reads as empty; an [otherProfiles]
  /// item [NamedProfile.tryFrom] cannot read, that repeats an id or takes
  /// the primary one is dropped, and the list is cut to
  /// [NamedProfile.maxProfiles] in all; an [activeProfileIds] id that
  /// names no profile, or repeats, is dropped, and an empty result reads as
  /// [defaultActiveProfileIds].
  ///
  /// [tripDestination] (ALG-13, issue #355) follows the "added later" rule
  /// too: a missing key, or a value [TripDestination.tryParse] does not
  /// recognise, reads as null — no trip — rather than invalidating the
  /// record.
  ///
  /// The monthly scan counter (ALG-18, issue #360) follows it too: a
  /// missing key, a value that is not a `{month, count}` object, a month
  /// that is not a string or a count that is not a positive integer reads
  /// as no scans counted.
  ///
  /// [shareConfirmations] (ALG-14, issue #409) follows it too: anything
  /// but a stored `true` reads as off.
  static AppSettings? tryFrom(Map<String, Object?> json) {
    final rawLanguageTag = json['languageTag'];
    if (rawLanguageTag != null && rawLanguageTag is! String) return null;
    final rawFilter = json['filter'];
    if (rawFilter is! String) return null;
    final filter = MenuFilter.tryParse(rawFilter);
    if (filter == null) return null;
    // D16 (issue #167) flipped the default to true. A stored value —
    // written by any install that reached [toJson] before or since —
    // wins over the default, so an install that already refused keeps
    // its refusal; a missing key on an install that predates
    // estimationConsentGiven at all reads as the new default rather than
    // invalidating the record.
    final rawConsent = json['estimationConsentGiven'];
    if (rawConsent != null && rawConsent is! bool) return null;
    final rawLastVenue = json['lastVenue'];
    VenueRef? lastVenue;
    if (rawLastVenue != null) {
      if (rawLastVenue is! Map<String, Object?>) return null;
      lastVenue = VenueRef.tryFrom(rawLastVenue);
      if (lastVenue == null) return null;
    }
    final rawThemeMode = json['themeMode'];
    final themeMode = rawThemeMode is String
        ? AppThemeMode.tryParse(rawThemeMode) ?? AppThemeMode.system
        : AppThemeMode.system;
    final rawLimit = json['netCarbLimitGrams'];
    final netCarbLimitGrams = rawLimit is int
        ? clampNetCarbLimitGrams(rawLimit)
        : defaultNetCarbLimitGrams;
    final rawLastFilter = json['lastFilter'];
    final lastFilter = rawLastFilter is String
        ? MenuFilter.tryParse(rawLastFilter)
        : null;
    final others = _readOthers(json[_otherProfilesKey]);
    final scans = _readScans(json[_monthlyScansKey]);
    return AppSettings(
      languageTag: rawLanguageTag is String ? rawLanguageTag : null,
      filter: filter,
      // Missing key → D16 default of true (issue #167); a stored bool
      // wins. The earlier guard rejects any non-null non-bool, so by
      // here rawConsent is null, true, or false.
      estimationConsentGiven: rawConsent != false,
      lastVenue: lastVenue,
      themeMode: themeMode,
      netCarbLimitGrams: netCarbLimitGrams,
      seedOilFree: json['seedOilFree'] == true,
      dairyFree: json['dairyFree'] == true,
      carnivoreOnly: json['carnivoreOnly'] == true,
      lastFilter: lastFilter,
      disclosureSeen: json['disclosureSeen'] == true,
      profile: DietaryProfile.tryFrom(json[_profileKey]),
      onboardingSeen: json[_onboardingSeenKey] == true,
      primaryProfileName: _readName(json[_primaryNameKey]),
      otherProfiles: others,
      activeProfileIds: _readActive(json[_activeProfilesKey], others),
      tripDestination: switch (json[_tripKey]) {
        final String wire => TripDestination.tryParse(wire),
        _ => null,
      },
      disclosureCopyVersion: _readCopyVersion(json[_disclosureCopyVersionKey]),
      helperToolSeen: json[_helperToolSeenKey] == true,
      scanMonth: scans.month,
      scanCount: scans.count,
      shareConfirmations: json[_shareConfirmationsKey] == true,
      menuNudgeDismissed: json[_menuNudgeDismissedKey] == true,
      discoveryNudgeDismissed: json[_discoveryNudgeDismissedKey] == true,
    );
  }

  /// The month and count stored under [_monthlyScansKey]; see [tryFrom].
  static ({String month, int count}) _readScans(Object? raw) {
    const none = (month: '', count: 0);
    if (raw is! Map<String, Object?>) return none;
    final month = raw['month'];
    final count = raw['count'];
    if (month is! String || month.isEmpty || count is! int || count <= 0) {
      return none;
    }
    return (month: month, count: count);
  }

  /// [raw] as a disclosure copy version: a non-negative integer, else 0.
  static int _readCopyVersion(Object? raw) => raw is int && raw > 0 ? raw : 0;

  /// [raw] as a name, or empty when it is not a string.
  static String _readName(Object? raw) =>
      raw is String ? NamedProfile.normaliseName(raw) : '';

  /// The other profiles stored under [_otherProfilesKey]; see [tryFrom].
  static List<NamedProfile> _readOthers(Object? raw) {
    if (raw is! List<Object?>) return const <NamedProfile>[];
    final seen = <String>{NamedProfile.primaryId};
    final others = <NamedProfile>[];
    for (final item in raw) {
      if (others.length == NamedProfile.maxProfiles - 1) break;
      final named = NamedProfile.tryFrom(item);
      if (named == null || !seen.add(named.id)) continue;
      others.add(named);
    }
    return List<NamedProfile>.unmodifiable(others);
  }

  /// The active ids stored under [_activeProfilesKey], kept only when they
  /// name the primary profile or one of [others]; see [tryFrom].
  static List<String> _readActive(Object? raw, List<NamedProfile> others) {
    if (raw is! List<Object?>) return defaultActiveProfileIds;
    final known = <String>{
      NamedProfile.primaryId,
      for (final other in others) other.id,
    };
    final active = <String>[];
    for (final id in raw.whereType<String>()) {
      if (known.contains(id) && !active.contains(id)) active.add(id);
    }
    return active.isEmpty
        ? defaultActiveProfileIds
        : List<String>.unmodifiable(active);
  }

  /// The JSON key [primaryProfileName] is stored under, written only when
  /// the user renamed their own profile. With [_otherProfilesKey] and
  /// [_activeProfilesKey], none is written while the device holds the one
  /// default profile, so that user's stored record is what it was before
  /// group profiles existed (ALG-12), and a keto user's stays
  /// byte-identical.
  static const String _primaryNameKey = 'profileName';

  /// The JSON key [otherProfiles] is stored under, written only when there
  /// is one.
  static const String _otherProfilesKey = 'groupProfiles';

  /// The JSON key [activeProfileIds] is stored under, written only when it
  /// differs from [defaultActiveProfileIds].
  static const String _activeProfilesKey = 'activeProfiles';

  /// The JSON key [tripDestination] is stored under (ALG-13), written only
  /// while a trip is active, so a keto install's stored record — and
  /// `const AppSettings().toJson()`, which `keto_unchanged_test` pins —
  /// stays byte-identical.
  static const String _tripKey = 'tripDestination';

  /// The JSON key [onboardingSeen] is stored under. [toJson] writes it only
  /// when it is true, for the same reason as [_profileKey]: a keto build
  /// never sets it, so its stored record stays byte-identical.
  static const String _onboardingSeenKey = 'restrictionOnboardingSeen';

  /// The JSON key [disclosureCopyVersion] is stored under, written only
  /// when it is above 0, so a keto build, which never sets it, keeps its
  /// stored record byte-identical.
  static const String _disclosureCopyVersionKey = 'disclosureCopyVersion';

  /// The JSON key [helperToolSeen] is stored under, written only when it
  /// is true, for the same reason.
  static const String _helperToolSeenKey = 'helperToolSeen';

  /// The JSON key the monthly scan counter ([scanMonth], [scanCount]) is
  /// stored under (ALG-18), as one `{month, count}` object written only
  /// while the count is above 0, so a keto install's stored record — and
  /// `const AppSettings().toJson()`, which `keto_unchanged_test` pins —
  /// stays byte-identical. Only a Banto build counts scans.
  static const String _monthlyScansKey = 'monthlyScans';

  /// The JSON key [shareConfirmations] is stored under (ALG-14, issue
  /// #409), written only when it is true, so a keto install's stored
  /// record — and `const AppSettings().toJson()`, which
  /// `keto_unchanged_test` pins — stays byte-identical.
  static const String _shareConfirmationsKey = 'shareConfirmations';

  /// The JSON key [menuNudgeDismissed] is stored under (issue #421),
  /// written only when it is true, so a keto install's stored record — and
  /// `const AppSettings().toJson()`, which `keto_unchanged_test` pins —
  /// stays byte-identical.
  static const String _menuNudgeDismissedKey = 'profileNudgeMenuDismissed';

  /// The JSON key [discoveryNudgeDismissed] is stored under (issue #421),
  /// written only when it is true, for the same reason.
  static const String _discoveryNudgeDismissedKey =
      'profileNudgeDiscoveryDismissed';

  /// The JSON key [profile] is stored under. [toJson] writes it only for a
  /// non-empty profile, so a keto-only install's stored record — and
  /// `const AppSettings().toJson()`, which `keto_unchanged_test` pins — is
  /// byte-identical to before the profile existed.
  static const String _profileKey = 'dietaryProfile';

  /// The UI language, as a BCP-47 tag such as `"he"`. Null means "follow
  /// the device locale".
  final String? languageTag;

  /// Which verdicts the menu view keeps.
  final MenuFilter filter;

  /// Whether the user has agreed to AI-estimated net-carb figures.
  final bool estimationConsentGiven;

  /// The last venue opened, or null before any venue has been.
  final VenueRef? lastVenue;

  /// The appearance choice: system, light, or dark (issue #58).
  final AppThemeMode themeMode;

  /// The net-carb limit in grams above which no dish is green (issue #57),
  /// within [minNetCarbLimitGrams]..[maxNetCarbLimitGrams] whenever it was
  /// read back through [tryFrom] or set through `SettingsController`.
  final int netCarbLimitGrams;

  /// Whether the "Strict seed-oil free" toggle is on (issue #56).
  final bool seedOilFree;

  /// Whether the "Dairy-free keto" toggle is on (issue #56).
  final bool dairyFree;

  /// Whether the "Carnivore only" toggle is on (issue #56).
  final bool carnivoreOnly;

  /// The verdict filter most recently chosen on the menu screen (issue
  /// #55), or null before any has been chosen. Kept separate from
  /// [filter] — the *default* filter set on the Settings screen — so the
  /// two never fight: `MenuController.setFilter` writes this field, and
  /// `MenuController.open` restores it over [filter] when it is set,
  /// falling back to [filter] otherwise.
  final MenuFilter? lastFilter;

  /// Whether the first-launch AI-analysis disclosure banner (D16, issue
  /// #167) has already been shown and acknowledged.
  ///
  /// The banner appears on Explore only while this is false; either
  /// button on the banner sets it to true, and the setting persists so
  /// the banner is never shown twice on the same install. Independent
  /// of [estimationConsentGiven]: dismissing the banner with "OK"
  /// leaves consent as-is; dismissing it with "Turn off" also sets
  /// consent to false. Missing or non-boolean values decode to false —
  /// the "not seen yet" state — following the same "added later" rule
  /// as [themeMode] and the dietary toggles.
  ///
  /// The banner itself lives in
  /// `lib/widgets/consent_disclosure_banner.dart`.
  final bool disclosureSeen;

  /// The restrictions the user chose (Banto, ALG-02a, issue #344);
  /// [DietaryProfile.empty] until they choose one. Kept on the device only
  /// (contract decision C1): this store writes it to `shared_preferences`
  /// and nothing else; no request body is built here.
  final DietaryProfile profile;

  /// Whether the first-run "What do you avoid?" onboarding (Banto,
  /// ALG-02b, issue #344) has been completed or skipped. False until then,
  /// and only ever set in a Banto build, so a keto install never writes it.
  /// A missing or non-boolean value reads as false.
  final bool onboardingSeen;

  /// The name the user gave their own profile (ALG-12, issue #354); empty
  /// until they rename it, which the UI shows as "Me" in its language.
  final String primaryProfileName;

  /// Everyone else's profiles on this device, in the order they were added
  /// (ALG-12, issue #354); none until the user adds a person. Kept on the
  /// device only, like [profile].
  final List<NamedProfile> otherProfiles;

  /// The ids of the profiles a menu is read for, in the order they were
  /// combined (ALG-12): the primary profile alone by default. Read through
  /// [activeProfiles], which drops an id that names no profile.
  final List<String> activeProfileIds;

  /// Where the user is travelling (Banto, ALG-13, issue #355), or null
  /// when trip mode is off. Sits beside the profile, never inside it, and
  /// like it stays on the device (contract decision C1): the evaluator
  /// reads the destination's lexicon on the device and nothing sends it.
  final TripDestination? tripDestination;

  /// The jurisdiction of [tripDestination], whose allergen law the trip's
  /// regulation hints read; null when trip mode is off.
  Jurisdiction? get tripJurisdiction => tripDestination?.jurisdiction;

  /// The version of the AI-disclosure copy the user last acknowledged
  /// (Banto, ALG-11, issue #353); 0 for the original keto copy. A Banto
  /// build whose disclosure says more (what of the profile leaves the
  /// device) shows the banner once more while this is below its own
  /// version, so a changed copy is read once. A missing, non-integer or
  /// negative value reads as 0.
  final int disclosureCopyVersion;

  /// Whether the helper-tool sheet ("A helper, not a guarantee") has been
  /// shown (Banto, ALG-11, issue #353): it appears once, when the first
  /// restriction of any kind is added. The first-run onboarding sets it,
  /// since that screen carries the same sentence. A missing or non-boolean
  /// value reads as false.
  final bool helperToolSeen;

  /// The month [scanCount] counts, as `YYYY-MM` (`scanMonthKey`); empty
  /// before the first scan is counted (Banto, ALG-18, issue #360).
  final String scanMonth;

  /// How many scans were read in [scanMonth]: what the free plan's monthly
  /// limit reads. Kept on the device only, and never sent.
  final int scanCount;

  /// The scans counted in [month]: [scanCount] when it is [scanMonth], and
  /// 0 for any other month, so a new month starts from nothing without a
  /// write.
  int scansIn(String month) => month == scanMonth ? scanCount : 0;

  /// Whether the user chose to share what the staff told them after a
  /// meal (Banto, ALG-14, issue #409): a consent of its own, off by
  /// default and separate from [estimationConsentGiven]. When it is on
  /// and the build has a backend, each answer saved in the post-meal
  /// prompt is sent as one fact — the venue, the dish's fingerprint, the
  /// one restriction asked about and yes or no — never the profile, a
  /// note or the change answer.
  final bool shareConfirmations;

  /// Whether the user dismissed the "Tell Banto what you avoid" notice on
  /// the menu screen (Banto, issue #421). Remembered per surface; a missing
  /// or non-boolean value reads as false, and a keto build never sets it.
  final bool menuNudgeDismissed;

  /// Whether the user dismissed the same notice on Discovery (issue #421);
  /// see [menuNudgeDismissed].
  final bool discoveryNudgeDismissed;

  /// Whether the notice of [surface] has been dismissed (issue #421).
  bool nudgeDismissed(ProfileNudgeSurface surface) => switch (surface) {
    ProfileNudgeSurface.menu => menuNudgeDismissed,
    ProfileNudgeSurface.discovery => discoveryNudgeDismissed,
  };

  /// Every profile on the device: the user's own ([profile], under
  /// [primaryProfileName]) first, then [otherProfiles].
  List<NamedProfile> get profiles => <NamedProfile>[
    NamedProfile(
      id: NamedProfile.primaryId,
      name: primaryProfileName,
      profile: profile,
    ),
    ...otherProfiles,
  ];

  /// The profiles a menu is read for, in [profiles]' order; the primary
  /// profile alone when [activeProfileIds] names none that exists, so it is
  /// never empty.
  List<NamedProfile> get activeProfiles {
    final all = profiles;
    final active = <NamedProfile>[
      for (final named in all)
        if (activeProfileIds.contains(named.id)) named,
    ];
    return active.isEmpty ? <NamedProfile>[all.first] : active;
  }

  /// Whether any profile a menu is read for holds a restriction besides
  /// keto: what turns ingredient extraction on (D26 C2). With the one
  /// default profile, exactly `profile.hasNonKetoEntry`.
  bool get activeHasNonKetoEntry =>
      activeProfiles.any((named) => named.profile.hasNonKetoEntry);

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitting [languageTag], [lastVenue] or [lastFilter] leaves the
  /// current value in place; passing `null` explicitly for any of them
  /// clears it. This is done by defaulting all three to a private
  /// sentinel distinct from `null`, so "not passed" and "passed null" can
  /// be told apart. [themeMode] has no such "clear it" meaning — it
  /// always names a real mode — so it uses the ordinary "omit to keep"
  /// default every other non-nullable field here would use, as do
  /// [netCarbLimitGrams] and the three dietary toggles. [tripDestination]
  /// takes the sentinel too: passing null switches trip mode off.
  AppSettings copyWith({
    Object? languageTag = _unset,
    MenuFilter? filter,
    bool? estimationConsentGiven,
    Object? lastVenue = _unset,
    AppThemeMode? themeMode,
    int? netCarbLimitGrams,
    bool? seedOilFree,
    bool? dairyFree,
    bool? carnivoreOnly,
    Object? lastFilter = _unset,
    bool? disclosureSeen,
    DietaryProfile? profile,
    bool? onboardingSeen,
    String? primaryProfileName,
    List<NamedProfile>? otherProfiles,
    List<String>? activeProfileIds,
    Object? tripDestination = _unset,
    int? disclosureCopyVersion,
    bool? helperToolSeen,
    String? scanMonth,
    int? scanCount,
    bool? shareConfirmations,
    bool? menuNudgeDismissed,
    bool? discoveryNudgeDismissed,
  }) => AppSettings(
    languageTag: identical(languageTag, _unset)
        ? this.languageTag
        : languageTag as String?,
    filter: filter ?? this.filter,
    estimationConsentGiven:
        estimationConsentGiven ?? this.estimationConsentGiven,
    lastVenue: identical(lastVenue, _unset)
        ? this.lastVenue
        : lastVenue as VenueRef?,
    themeMode: themeMode ?? this.themeMode,
    netCarbLimitGrams: netCarbLimitGrams ?? this.netCarbLimitGrams,
    seedOilFree: seedOilFree ?? this.seedOilFree,
    dairyFree: dairyFree ?? this.dairyFree,
    carnivoreOnly: carnivoreOnly ?? this.carnivoreOnly,
    lastFilter: identical(lastFilter, _unset)
        ? this.lastFilter
        : lastFilter as MenuFilter?,
    disclosureSeen: disclosureSeen ?? this.disclosureSeen,
    profile: profile ?? this.profile,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
    primaryProfileName: primaryProfileName ?? this.primaryProfileName,
    otherProfiles: otherProfiles ?? this.otherProfiles,
    activeProfileIds: activeProfileIds ?? this.activeProfileIds,
    tripDestination: identical(tripDestination, _unset)
        ? this.tripDestination
        : tripDestination as TripDestination?,
    disclosureCopyVersion: disclosureCopyVersion ?? this.disclosureCopyVersion,
    helperToolSeen: helperToolSeen ?? this.helperToolSeen,
    scanMonth: scanMonth ?? this.scanMonth,
    scanCount: scanCount ?? this.scanCount,
    shareConfirmations: shareConfirmations ?? this.shareConfirmations,
    menuNudgeDismissed: menuNudgeDismissed ?? this.menuNudgeDismissed,
    discoveryNudgeDismissed:
        discoveryNudgeDismissed ?? this.discoveryNudgeDismissed,
  );

  /// Writes a form [tryFrom] can read back. [profile] is written only
  /// when it is not empty, and [onboardingSeen] only when it is true; see
  /// [_profileKey] and [_onboardingSeenKey]. The group profile fields are
  /// written only when they differ from their defaults; see
  /// [_primaryNameKey]. [tripDestination] is written only while a trip is
  /// active; see [_tripKey]. So are [disclosureCopyVersion] and
  /// [helperToolSeen] (ALG-11). The scan counter is written only while it
  /// counts a scan; see [_monthlyScansKey]. [shareConfirmations] is
  /// written only when it is on; see [_shareConfirmationsKey]. The two
  /// nudge dismissals are written only when set; see
  /// [_menuNudgeDismissedKey].
  Map<String, Object?> toJson() => <String, Object?>{
    'languageTag': languageTag,
    'filter': filter.name,
    'estimationConsentGiven': estimationConsentGiven,
    'lastVenue': lastVenue?.toJson(),
    'themeMode': themeMode.name,
    'netCarbLimitGrams': netCarbLimitGrams,
    'seedOilFree': seedOilFree,
    'dairyFree': dairyFree,
    'carnivoreOnly': carnivoreOnly,
    'lastFilter': lastFilter?.name,
    'disclosureSeen': disclosureSeen,
    if (!profile.isEmpty) _profileKey: profile.toJson(),
    if (onboardingSeen) _onboardingSeenKey: true,
    if (primaryProfileName.isNotEmpty) _primaryNameKey: primaryProfileName,
    if (otherProfiles.isNotEmpty)
      _otherProfilesKey: <Map<String, Object?>>[
        for (final other in otherProfiles) other.toJson(),
      ],
    if (!listEquals(activeProfileIds, defaultActiveProfileIds))
      _activeProfilesKey: activeProfileIds,
    if (tripDestination case final trip?) _tripKey: trip.name,
    if (disclosureCopyVersion > 0)
      _disclosureCopyVersionKey: disclosureCopyVersion,
    if (helperToolSeen) _helperToolSeenKey: true,
    if (scanCount > 0 && scanMonth.isNotEmpty)
      _monthlyScansKey: <String, Object?>{
        'month': scanMonth,
        'count': scanCount,
      },
    if (shareConfirmations) _shareConfirmationsKey: true,
    if (menuNudgeDismissed) _menuNudgeDismissedKey: true,
    if (discoveryNudgeDismissed) _discoveryNudgeDismissedKey: true,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.languageTag == languageTag &&
      other.filter == filter &&
      other.estimationConsentGiven == estimationConsentGiven &&
      other.lastVenue == lastVenue &&
      other.themeMode == themeMode &&
      other.netCarbLimitGrams == netCarbLimitGrams &&
      other.seedOilFree == seedOilFree &&
      other.dairyFree == dairyFree &&
      other.carnivoreOnly == carnivoreOnly &&
      other.lastFilter == lastFilter &&
      other.disclosureSeen == disclosureSeen &&
      other.profile == profile &&
      other.onboardingSeen == onboardingSeen &&
      other.primaryProfileName == primaryProfileName &&
      listEquals(other.otherProfiles, otherProfiles) &&
      listEquals(other.activeProfileIds, activeProfileIds) &&
      other.tripDestination == tripDestination &&
      other.disclosureCopyVersion == disclosureCopyVersion &&
      other.helperToolSeen == helperToolSeen &&
      other.scanMonth == scanMonth &&
      other.scanCount == scanCount &&
      other.shareConfirmations == shareConfirmations &&
      other.menuNudgeDismissed == menuNudgeDismissed &&
      other.discoveryNudgeDismissed == discoveryNudgeDismissed;

  @override
  int get hashCode => Object.hash(
    languageTag,
    filter,
    estimationConsentGiven,
    lastVenue,
    themeMode,
    netCarbLimitGrams,
    seedOilFree,
    dairyFree,
    carnivoreOnly,
    lastFilter,
    disclosureSeen,
    profile,
    onboardingSeen,
    primaryProfileName,
    Object.hashAll(otherProfiles),
    Object.hashAll(activeProfileIds),
    tripDestination,
    disclosureCopyVersion,
    helperToolSeen,
    // Object.hash takes at most 20 values; the last five hash as one.
    Object.hash(
      scanMonth,
      scanCount,
      shareConfirmations,
      menuNudgeDismissed,
      discoveryNudgeDismissed,
    ),
  );

  @override
  String toString() =>
      'AppSettings(lang: $languageTag, filter: $filter, '
      'consent: $estimationConsentGiven, themeMode: $themeMode, '
      'netCarbLimit: ${netCarbLimitGrams}g, lastFilter: $lastFilter, '
      'seedOilFree: $seedOilFree, dairyFree: $dairyFree, '
      'carnivoreOnly: $carnivoreOnly, '
      'disclosureSeen: $disclosureSeen, '
      // A count, never the restrictions themselves, so a logged settings
      // value cannot carry the profile (contract decision C1).
      'profile: ${profile.entries.length} entries, '
      'onboardingSeen: $onboardingSeen, '
      // Counts again, never names (C1).
      'otherProfiles: ${otherProfiles.length}, '
      'active: ${activeProfileIds.length}, '
      // Whether a trip is on, never where (C1).
      'trip: ${tripDestination != null}, '
      'disclosureCopyVersion: $disclosureCopyVersion, '
      'helperToolSeen: $helperToolSeen, '
      'scans: $scanCount in $scanMonth, '
      'shareConfirmations: $shareConfirmations)';
}

/// On-device storage for [AppSettings] (architecture.md §6.4). Backed by
/// `shared_preferences`.
abstract interface class SettingsStore {
  /// The stored settings, or [AppSettings] defaults when none have been
  /// saved, or when storage failed to read.
  ///
  /// Never null. Never throws.
  Future<AppSettings> read();

  /// Saves [settings], replacing any previously stored value.
  ///
  /// Never throws.
  Future<void> write(AppSettings settings);
}

/// The shared_preferences key [AppSettings] is stored under, as one JSON
/// string written by [AppSettings.toJson] (architecture.md §6.4).
const String _settingsStorageKey = 'ketoclub_settings';

/// A [SettingsStore] over `shared_preferences`.
///
/// The loader passed to the constructor — `SharedPreferences.getInstance`
/// in `di.dart`, a test double elsewhere — is invoked lazily and at most
/// once: `di.dart` must not perform plugin I/O while building the
/// dependency graph — `buildDependencies()` runs from `main()` and from
/// tests that hold no plugin binding — so the resolved instance is
/// memoised the same way `HiveMenuCache` memoises its opened box.
final class PrefsSettingsStore implements SettingsStore {
  /// Creates a store whose backing preferences are obtained by calling
  /// [load] on first use.
  new({required this.load});

  /// Loads (or opens) the backing preferences. Invoked at most once; see
  /// [_preferences].
  final Future<SharedPreferences> Function() load;

  /// The preferences, once loaded. Holds the in-flight (or completed)
  /// future rather than a `SharedPreferences` directly, so nothing here
  /// touches preferences before [load] has actually run.
  Future<SharedPreferences>? _prefs;

  /// Returns the preferences, loading them via [load] on the first call
  /// and reusing that result on every later call.
  Future<SharedPreferences> _preferences() => _prefs ??= load();

  @override
  Future<AppSettings> read() async {
    final SharedPreferences prefs;
    try {
      prefs = await _preferences();
      // A broken loader reads back as defaults (architecture.md §6.4).
    } on Exception {
      return const AppSettings();
    }
    final raw = prefs.getString(_settingsStorageKey);
    if (raw == null) return const AppSettings();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const AppSettings();
    }
    if (decoded is! Map<String, Object?>) return const AppSettings();
    return AppSettings.tryFrom(decoded) ?? const AppSettings();
  }

  @override
  Future<void> write(AppSettings settings) async {
    final SharedPreferences prefs;
    try {
      prefs = await _preferences();
      // A broken loader drops the write; never throws.
    } on Exception {
      return;
    }
    final value = jsonEncode(settings.toJson());
    try {
      await prefs.setString(_settingsStorageKey, value);
      // Drop the write; a broken channel degrades instead of throwing.
    } on Exception {
      // Nothing to do: the write above never landed.
    }
  }
}
