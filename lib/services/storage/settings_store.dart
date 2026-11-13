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
import 'package:ketoclub/models/place.dart';
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
/// last-used filter (issue #55), the three "Your keto rules"
/// toggles (issue #56), whether the first-launch AI disclosure
/// banner has been seen (D16, issue #167), and the place chosen to look
/// around on the Discovery screen: a city (issue #443) or a street (issue
/// #449).
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
    this.discoveryPlaceId,
    this.discoveryStreet,
  });

  /// Reads settings written by [toJson].
  ///
  /// Read field by field (issue #281): never throws and never gives up on
  /// the record. A missing or unreadable value falls back to its own
  /// default and every other field keeps its stored value, so an unknown
  /// [filter] name reads as [MenuFilter.all] and a [lastVenue] that
  /// [VenueRef.tryFrom] cannot read as null. **Consent fails closed:** a
  /// present [estimationConsentGiven] that is not a bool reads as false.
  /// [themeMode] (issue #58) decodes to [AppThemeMode.system] when missing
  /// or unrecognised.
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
  /// [discoveryPlaceId] (issue #443) follows the same rule: a missing key,
  /// or a value that is not a non-empty string, decodes to null — "no
  /// place chosen".
  ///
  /// [discoveryStreet] (issue #449) follows it too: a missing key, or a
  /// value [StreetPlace.tryFrom] does not read, decodes to null. The two
  /// are never both set: a record holding both keeps the city and drops
  /// the street, since a city is the older and the cheaper choice to
  /// restore (it is never looked up again).
  static AppSettings? tryFrom(Map<String, Object?> json) {
    // Field by field (issue #281): one unreadable value falls back to its
    // own default and never resets the others.
    final rawFilter = json['filter'];
    final rawLastVenue = json['lastVenue'];
    final rawThemeMode = json['themeMode'];
    final rawLimit = json['netCarbLimitGrams'];
    final rawLastFilter = json['lastFilter'];
    final rawPlaceId = json['discoveryPlaceId'];
    final discoveryPlaceId = rawPlaceId is String && rawPlaceId.isNotEmpty
        ? rawPlaceId
        : null;
    final rawStreet = json['discoveryStreet'];
    final discoveryStreet =
        discoveryPlaceId == null && rawStreet is Map<String, Object?>
        ? StreetPlace.tryFrom(rawStreet)
        : null;
    return AppSettings(
      languageTag: switch (json['languageTag']) {
        final String tag => tag,
        _ => null,
      },
      filter: rawFilter is String
          ? MenuFilter.tryParse(rawFilter) ?? MenuFilter.all
          : MenuFilter.all,
      estimationConsentGiven: _readConsent(json['estimationConsentGiven']),
      lastVenue: rawLastVenue is Map<String, Object?>
          ? VenueRef.tryFrom(rawLastVenue)
          : null,
      themeMode: rawThemeMode is String
          ? AppThemeMode.tryParse(rawThemeMode) ?? AppThemeMode.system
          : AppThemeMode.system,
      netCarbLimitGrams: rawLimit is int
          ? clampNetCarbLimitGrams(rawLimit)
          : defaultNetCarbLimitGrams,
      seedOilFree: json['seedOilFree'] == true,
      dairyFree: json['dairyFree'] == true,
      carnivoreOnly: json['carnivoreOnly'] == true,
      lastFilter: rawLastFilter is String
          ? MenuFilter.tryParse(rawLastFilter)
          : null,
      disclosureSeen: json['disclosureSeen'] == true,
      discoveryPlaceId: discoveryPlaceId,
      discoveryStreet: discoveryStreet,
    );
  }

  /// [raw] as the stored consent, failing closed (issue #281): a missing
  /// key is the D16 default of true (issue #167), a bool is itself, and a
  /// value that is present but cannot be read is false. A parse failure
  /// may withdraw consent, never grant it.
  static bool _readConsent(Object? raw) => switch (raw) {
    null => true,
    final bool given => given,
    _ => false,
  };

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

  /// The id of the place the user chose to look around on the Discovery
  /// screen instead of the device's own position (issue #443) — a
  /// `KnownPlace.id` from `utils/known_places.dart` — or null when none is
  /// chosen.
  ///
  /// Only the id is stored, never coordinates: the list is the one source
  /// of where a place is. An id the list no longer holds is read back as
  /// it was written and simply not restored by `VenueSearchController`.
  final String? discoveryPlaceId;

  /// The street the user chose to look around on the Discovery screen
  /// (issue #449, architecture.md D28), or null when none is chosen.
  ///
  /// Stored as its label and coordinates only ([StreetPlace.toJson]),
  /// since a street, unlike a city, cannot be looked up again without
  /// sending the user's words to a geocoder. Never set together with
  /// [discoveryPlaceId]: `VenueSearchController` clears one whenever it
  /// writes the other, and [tryFrom] keeps only the city if both are
  /// found. It stays on the device: the only part of it that ever leaves
  /// is the latitude and longitude of the nearby search made around it.
  final StreetPlace? discoveryStreet;

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitting [languageTag], [lastVenue], [lastFilter],
  /// [discoveryPlaceId] or [discoveryStreet] leaves the current value in
  /// place; passing `null`
  /// explicitly for any of them clears it. This is done by defaulting each
  /// of them to a private
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
    bool? disclosureSeen,
    Object? discoveryPlaceId = _unset,
    Object? discoveryStreet = _unset,
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
    discoveryPlaceId: identical(discoveryPlaceId, _unset)
        ? this.discoveryPlaceId
        : discoveryPlaceId as String?,
    discoveryStreet: identical(discoveryStreet, _unset)
        ? this.discoveryStreet
        : discoveryStreet as StreetPlace?,
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
    'disclosureSeen': disclosureSeen,
    'discoveryPlaceId': discoveryPlaceId,
    'discoveryStreet': discoveryStreet?.toJson(),
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
      other.discoveryPlaceId == discoveryPlaceId &&
      other.discoveryStreet == discoveryStreet;

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
    discoveryPlaceId,
    discoveryStreet,
  );

  @override
  String toString() =>
      'AppSettings(lang: $languageTag, filter: $filter, '
      'consent: $estimationConsentGiven, themeMode: $themeMode, '
      'netCarbLimit: ${netCarbLimitGrams}g, lastFilter: $lastFilter, '
      'seedOilFree: $seedOilFree, dairyFree: $dairyFree, '
      'carnivoreOnly: $carnivoreOnly, '
      'disclosureSeen: $disclosureSeen, '
      'discoveryPlace: $discoveryPlaceId, '
      'discoveryStreet: ${discoveryStreet != null})';
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
  /// Replaces every field, so a [settings] read before another write
  /// lands undoes that write. A caller that changes some fields of what it
  /// read earlier uses [update] instead (issue #287).
  ///
  /// Never throws.
  Future<void> write(AppSettings settings);

  /// Applies [change] to the latest stored settings and saves the result,
  /// answering what was saved (issue #287): a read-modify-write, so a
  /// change to one field never reverts a field someone else wrote after
  /// the caller last read. An implementation runs one [update] at a time,
  /// in call order, so two overlapping updates both land.
  ///
  /// Never throws, unless [change] itself does.
  Future<AppSettings> update(AppSettings Function(AppSettings latest) change);
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

  /// The last queued operation; each [read], [write] and [update] runs
  /// after it, so they settle one at a time and in call order.
  Future<void> _tail = Future<void>.value();

  /// Runs [task] after every operation queued before it.
  Future<T> _serialised<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    // A failed task (only a throwing `update` change can fail) must not
    // stall the queue behind it.
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// What a stored record that cannot be decoded at all reads as: the
  /// defaults with consent withheld (issue #281). The stored consent may
  /// have been a refusal, and a parse failure never grants it.
  static const AppSettings _unreadable = AppSettings(
    estimationConsentGiven: false,
  );

  @override
  Future<AppSettings> read() => _serialised(_read);

  @override
  Future<void> write(AppSettings settings) =>
      _serialised(() => _write(settings));

  @override
  Future<AppSettings> update(AppSettings Function(AppSettings latest) change) =>
      _serialised(() async {
        final next = change(await _read());
        await _write(next);
        return next;
      });

  /// The stored settings; see [read].
  Future<AppSettings> _read() async {
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
      return _unreadable;
    }
    if (decoded is! Map<String, Object?>) return _unreadable;
    return AppSettings.tryFrom(decoded) ?? _unreadable;
  }

  /// Saves [settings]; see [write].
  Future<void> _write(AppSettings settings) async {
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
