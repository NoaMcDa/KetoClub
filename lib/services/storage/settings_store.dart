import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';

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
    return AppSettings(
      languageTag: rawLanguageTag is String ? rawLanguageTag : null,
      filter: filter,
      estimationConsentGiven: rawConsent,
      lastVenue: lastVenue,
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
  );

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'languageTag': languageTag,
    'filter': filter.name,
    'estimationConsentGiven': estimationConsentGiven,
    'lastVenue': lastVenue?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.languageTag == languageTag &&
      other.filter == filter &&
      other.estimationConsentGiven == estimationConsentGiven &&
      other.lastVenue == lastVenue;

  @override
  int get hashCode =>
      Object.hash(languageTag, filter, estimationConsentGiven, lastVenue);

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
