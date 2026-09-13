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
import 'package:shared_preferences/shared_preferences.dart';

/// Marks "leave this field unchanged" in [AppSettings.copyWith], distinct
/// from any real value the field can hold, including `null`. There is no
/// public way to obtain this object, so a caller can never pass it by
/// accident.
const Object _unset = Object();

/// The user's on-device preferences (architecture.md §6.4): UI language,
/// filter default, AI-estimation consent, and the last venue opened.
@immutable
final class AppSettings {
  /// Creates settings. Every field defaults to the "nothing set yet"
  /// value a virgin store should read back.
  const new({
    this.languageTag,
    this.filter = MenuFilter.greenAndYellow,
    this.estimationConsentGiven = false,
    this.lastVenue,
    this.backendUrl,
  });

  /// Reads settings written by [toJson].
  ///
  /// Returns null for any shape mismatch, including a malformed
  /// [lastVenue] or an unknown [filter] name, and never throws.
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
    final rawBackendUrl = json['backendUrl'];
    if (rawBackendUrl != null && rawBackendUrl is! String) return null;
    return AppSettings(
      languageTag: rawLanguageTag is String ? rawLanguageTag : null,
      filter: filter,
      estimationConsentGiven: rawConsent,
      lastVenue: lastVenue,
      backendUrl: rawBackendUrl is String ? rawBackendUrl : null,
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

  /// The KetoClub backend to route menu fetches through, overriding the
  /// compile-time `KETOCLUB_BACKEND_URL`, or null to use that value
  /// (architecture.md §13, D11).
  ///
  /// Its reason to exist is testing a phone build against a backend on
  /// the machine next to it, so unlike the compile-time value it applies
  /// on every platform, not only the web. Not a secret: it is a host the
  /// user typed, and it is stored beside the other preferences rather
  /// than in the key store.
  final String? backendUrl;

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitting [languageTag] or [lastVenue] leaves the current value in
  /// place; passing `null` explicitly for either clears it. This is done
  /// by defaulting both to a private sentinel distinct from `null`, so
  /// "not passed" and "passed null" can be told apart.
  AppSettings copyWith({
    Object? languageTag = _unset,
    MenuFilter? filter,
    bool? estimationConsentGiven,
    Object? lastVenue = _unset,
    Object? backendUrl = _unset,
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
    backendUrl: identical(backendUrl, _unset)
        ? this.backendUrl
        : backendUrl as String?,
  );

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'languageTag': languageTag,
    'filter': filter.name,
    'estimationConsentGiven': estimationConsentGiven,
    'lastVenue': lastVenue?.toJson(),
    'backendUrl': backendUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.languageTag == languageTag &&
      other.filter == filter &&
      other.estimationConsentGiven == estimationConsentGiven &&
      other.lastVenue == lastVenue &&
      other.backendUrl == backendUrl;

  @override
  int get hashCode => Object.hash(
    languageTag,
    filter,
    estimationConsentGiven,
    lastVenue,
    backendUrl,
  );

  @override
  String toString() =>
      'AppSettings(lang: $languageTag, filter: $filter, '
      'consent: $estimationConsentGiven)';
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
