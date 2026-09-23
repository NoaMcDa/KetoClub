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

/// The user's on-device preferences (architecture.md §6.4): UI language,
/// filter default, AI-estimation consent, the last venue opened, the
/// appearance (issue #58), the net-carb limit (issue #57), the
/// last-used filter (issue #55) and the three "Your keto rules"
/// toggles (issue #56).
@immutable
final class AppSettings {
  /// Creates settings. Every field defaults to the "nothing set yet"
  /// value a virgin store should read back.
  const new({
    this.languageTag,
    this.filter = MenuFilter.all,
    this.estimationConsentGiven = false,
    this.lastVenue,
    this.themeMode = AppThemeMode.system,
    this.netCarbLimitGrams = defaultNetCarbLimitGrams,
    this.seedOilFree = false,
    this.dairyFree = false,
    this.carnivoreOnly = false,
    this.lastFilter,
  });

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
  static AppSettings? tryFrom(Map<String, Object?> json) {
    final rawLanguageTag = json['languageTag'];
    if (rawLanguageTag != null && rawLanguageTag is! String) return null;
    final rawFilter = json['filter'];
    if (rawFilter is! String) return null;
    final filter = MenuFilter.tryParse(rawFilter);
    if (filter == null) return null;
    final rawConsent = json['estimationConsentGiven'];
    if (rawConsent is! bool) return null;
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
    return AppSettings(
      languageTag: rawLanguageTag is String ? rawLanguageTag : null,
      filter: filter,
      estimationConsentGiven: rawConsent,
      lastVenue: lastVenue,
      themeMode: themeMode,
      netCarbLimitGrams: netCarbLimitGrams,
      seedOilFree: json['seedOilFree'] == true,
      dairyFree: json['dairyFree'] == true,
      carnivoreOnly: json['carnivoreOnly'] == true,
      lastFilter: lastFilter,
    );
  }

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

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitting [languageTag], [lastVenue] or [lastFilter] leaves the
  /// current value in place; passing `null` explicitly for any of them
  /// clears it. This is done by defaulting all three to a private
  /// sentinel distinct from `null`, so "not passed" and "passed null" can
  /// be told apart. [themeMode] has no such "clear it" meaning — it
  /// always names a real mode — so it uses the ordinary "omit to keep"
  /// default every other non-nullable field here would use, as do
  /// [netCarbLimitGrams] and the three dietary toggles.
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
  );

  /// Writes a form [tryFrom] can read back.
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
      other.lastFilter == lastFilter;

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
  );

  @override
  String toString() =>
      'AppSettings(lang: $languageTag, filter: $filter, '
      'consent: $estimationConsentGiven, themeMode: $themeMode, '
      'netCarbLimit: ${netCarbLimitGrams}g, lastFilter: $lastFilter, '
      'seedOilFree: $seedOilFree, dairyFree: $dairyFree, '
      'carnivoreOnly: $carnivoreOnly)';
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
