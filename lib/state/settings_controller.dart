import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/storage/api_key_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// Screen state for the Settings screen (architecture.md §6.6).
///
/// Reads and writes the user's preferences — including whether dish text
/// may be sent for AI analysis — through a [SettingsStore], and delegates
/// cache clearing to a [MenuRepository].
///
/// On iOS and Android it also saves and removes the user's own Gemini API
/// key through an [ApiKeyStore] (architecture.md D17); on web there is no
/// store, [supportsApiKey] is false, and the model key lives on the
/// server (D12). **Never exposes the key itself** — only [hasApiKey], a
/// presence flag — because the key is read solely by `GeminiChatClient`
/// and is never logged, never in a failure value and never in the cache
/// (§11); a getter that returned it, or a field that outlived
/// [saveApiKey], would be a way around that rule.
///
/// Never throws — every service behind it already returns values instead
/// of throwing, or promises not to (architecture.md §18.1).
final class SettingsController extends ChangeNotifier {
  /// Creates a controller over a [SettingsStore], a [MenuRepository] and,
  /// on iOS and Android, an [ApiKeyStore].
  ///
  /// The services are positional and private, matching
  /// `MenuController`: private because a widget reaches a service only
  /// through a controller's own API (architecture.md §5) and a public
  /// field would hand it a way around this class; positional, because a
  /// private field cannot be a named initializing formal in Dart and the
  /// alternative was suppressing a lint on every field. The distinct
  /// types mean a misordered call does not compile.
  /// The key store is optional because the web build has none. The visit
  /// history defaults to [NoVisitHistoryStore], which remembers nothing
  /// (issue #307).
  new(
    this._settings,
    this._repository, [
    this._apiKeyStore,
    this._history = const NoVisitHistoryStore(),
  ]);

  final SettingsStore _settings;
  final MenuRepository _repository;
  final ApiKeyStore? _apiKeyStore;

  /// The menus opened on this device (issue #307). [clearCache] empties it
  /// along with the saved menus (issue #314, D23).
  final VisitHistoryStore _history;

  bool _isBusy = false;
  AppSettings _appSettings = const AppSettings();
  int _cachedMenuCount = 0;
  bool _hasApiKey = false;

  /// Whether an operation is currently reading from or writing to a
  /// store.
  bool get isBusy => _isBusy;

  /// Whether the user has allowed AI analysis: dish text sent to the
  /// model provider — straight to Google on iOS and Android (D17), through
  /// KetoClub's server on web (D12).
  bool get consentGiven => _appSettings.estimationConsentGiven;

  /// Whether this build takes the user's own Gemini API key: true on iOS
  /// and Android, false on web (architecture.md D17). Settings shows the
  /// key field, and the direct-to-Google disclosure, only when it is.
  bool get supportsApiKey => _apiKeyStore != null;

  /// Whether a Gemini API key is currently saved. Always false when
  /// [supportsApiKey] is. Never the key itself — see the class doc.
  bool get hasApiKey => _hasApiKey;

  /// The UI language, as a BCP-47 tag, or null to follow the device
  /// locale.
  String? get languageTag => _appSettings.languageTag;

  /// Which verdicts the menu view keeps by default.
  MenuFilter get filter => _appSettings.filter;

  /// The appearance choice: system, light, or dark (issue #58).
  AppThemeMode get themeMode => _appSettings.themeMode;

  /// The net-carb limit in grams above which no dish is green (issue #57).
  int get netCarbLimitGrams => _appSettings.netCarbLimitGrams;

  /// Whether the "Strict seed-oil free" rule is on (issue #56).
  bool get seedOilFree => _appSettings.seedOilFree;

  /// Whether the "Dairy-free keto" rule is on (issue #56).
  bool get dairyFree => _appSettings.dairyFree;

  /// Whether the "Carnivore only" rule is on (issue #56).
  bool get carnivoreOnly => _appSettings.carnivoreOnly;

  /// Whether the first-launch AI-disclosure banner has already been
  /// shown on this install (D16, issue #167). Persisted on
  /// [AppSettings.disclosureSeen]; the banner itself reads the store
  /// directly rather than through this controller, so this getter is a
  /// convenience for tests and any future caller in a scope that
  /// already holds a controller.
  bool get disclosureSeen => _appSettings.disclosureSeen;

  /// The restrictions the user chose (Banto, ALG-02a, issue #344), kept on
  /// this device only (contract decision C1).
  DietaryProfile get profile => _appSettings.profile;

  /// Whether the first-run restriction onboarding has been completed or
  /// skipped (Banto, ALG-02b, issue #344).
  bool get onboardingSeen => _appSettings.onboardingSeen;

  /// Whether the helper-tool sheet has been shown (Banto, ALG-11, issue
  /// #353); see [AppSettings.helperToolSeen].
  bool get helperToolSeen => _appSettings.helperToolSeen;

  /// Whether the user shares what the staff told them after a meal
  /// (Banto, ALG-14, issue #409); see [AppSettings.shareConfirmations].
  bool get shareConfirmations => _appSettings.shareConfirmations;

  /// How many menus are currently cached (issue #61's Settings section). A
  /// count of entries, never a byte figure —
  /// [MenuRepository.cachedMenuCount]'s own doc comment explains why.
  int get cachedMenuCount => _cachedMenuCount;

  /// Reads the [SettingsStore] and the cached-menu count, populating every
  /// other getter.
  Future<void> load() async {
    _isBusy = true;
    notifyListeners();

    _appSettings = await _settings.read();
    _cachedMenuCount = await _repository.cachedMenuCount();
    _hasApiKey = await _apiKeyStore?.hasKey() ?? false;

    _isBusy = false;
    notifyListeners();
  }

  /// Saves [key], trimmed, as the user's Gemini API key (architecture.md
  /// D17).
  ///
  /// A key that is empty or only whitespace is **not written**: Gemini
  /// would reject it regardless, so storing it would only replace "no
  /// key" with a value guaranteed to fail. Also a no-op when
  /// [supportsApiKey] is false. [hasApiKey] is re-read from the store
  /// afterwards rather than assumed, so a write the platform dropped
  /// shows as "no key".
  Future<void> saveApiKey(String key) async {
    final store = _apiKeyStore;
    final trimmed = key.trim();
    if (store == null || trimmed.isEmpty) return;

    _isBusy = true;
    notifyListeners();

    await store.write(trimmed);
    _hasApiKey = await store.hasKey();

    _isBusy = false;
    notifyListeners();
  }

  /// Removes the saved Gemini API key, if any; the next menu opened falls
  /// back to the rules engine, saying why. A no-op when [supportsApiKey]
  /// is false.
  Future<void> deleteApiKey() async {
    final store = _apiKeyStore;
    if (store == null) return;

    _isBusy = true;
    notifyListeners();

    await store.delete();
    _hasApiKey = await store.hasKey();

    _isBusy = false;
    notifyListeners();
  }

  /// Records whether the user agrees to the disclosure in Settings that dish
  /// text is sent to the model provider for analysis — directly on iOS and
  /// Android, through KetoClub's server on web (architecture.md §11).
  ///
  /// Named rather than positional so a call site reads as a sentence, which
  /// also avoids suppressing `avoid_positional_boolean_parameters`.
  Future<void> setConsent({required bool given}) async {
    _isBusy = true;
    notifyListeners();

    _appSettings = _appSettings.copyWith(estimationConsentGiven: given);
    await _settings.write(_appSettings);

    _isBusy = false;
    notifyListeners();
  }

  /// Sets the UI language to [tag], or clears it — meaning "follow the
  /// device locale" — when [tag] is null.
  ///
  /// [tag] is always passed through to [AppSettings.copyWith]
  /// explicitly, including when it is null, so the sentinel that
  /// `copyWith` uses to mean "leave this field alone" is never mistaken
  /// for a real value: passing null here always clears the tag.
  Future<void> setLanguage(String? tag) async {
    _isBusy = true;
    notifyListeners();

    _appSettings = _appSettings.copyWith(languageTag: tag);
    await _settings.write(_appSettings);

    _isBusy = false;
    notifyListeners();
  }

  /// Sets the default menu filter to [filter].
  Future<void> setFilter(MenuFilter filter) async {
    _isBusy = true;
    notifyListeners();

    _appSettings = _appSettings.copyWith(filter: filter);
    await _settings.write(_appSettings);

    _isBusy = false;
    notifyListeners();
  }

  /// Sets the appearance mode to [mode] (issue #58).
  Future<void> setThemeMode(AppThemeMode mode) async {
    _isBusy = true;
    notifyListeners();

    _appSettings = _appSettings.copyWith(themeMode: mode);
    await _settings.write(_appSettings);

    _isBusy = false;
    notifyListeners();
  }

  /// Sets the net-carb limit to [grams], clamped to
  /// [minNetCarbLimitGrams]..[maxNetCarbLimitGrams] (issue #57).
  ///
  /// Clamped here as well as on decode, so no caller — the Settings
  /// stepper or anything after it — can persist a limit the stepper could
  /// not show. The next menu opened is re-analysed under the new limit;
  /// see `MenuController.open`.
  Future<void> setNetCarbLimit(int grams) async {
    _isBusy = true;
    notifyListeners();

    _appSettings = _appSettings.copyWith(
      netCarbLimitGrams: clampNetCarbLimitGrams(grams),
    );
    await _settings.write(_appSettings);

    _isBusy = false;
    notifyListeners();
  }

  /// Turns the "Strict seed-oil free" rule on or off (issue #56).
  ///
  /// Like every dietary toggle, it changes the options the next menu is
  /// analysed under, so that open re-analyses rather than reusing a
  /// cached result; see `MenuController.open`. Named rather than
  /// positional for the reason [setConsent] gives.
  Future<void> setSeedOilFree({required bool enabled}) =>
      _update(_appSettings.copyWith(seedOilFree: enabled));

  /// Turns the "Dairy-free keto" rule on or off (issue #56). See
  /// [setSeedOilFree].
  Future<void> setDairyFree({required bool enabled}) =>
      _update(_appSettings.copyWith(dairyFree: enabled));

  /// Turns the "Carnivore only" rule on or off (issue #56). See
  /// [setSeedOilFree].
  Future<void> setCarnivoreOnly({required bool enabled}) =>
      _update(_appSettings.copyWith(carnivoreOnly: enabled));

  /// Records that the first-launch AI-disclosure banner has been
  /// dismissed with "OK" (D16, issue #167). Leaves
  /// [consentGiven] unchanged — the user acknowledged the disclosure
  /// but did not refuse — and persists [disclosureSeen] as true so the
  /// banner is never shown twice on the same install.
  Future<void> acknowledgeDisclosure() =>
      _update(_appSettings.copyWith(disclosureSeen: true));

  /// Records that the first-launch AI-disclosure banner has been
  /// dismissed with "Turn off" (D16, issue #167): consent is set to
  /// false in the same write as [disclosureSeen] is set to true, so the
  /// router stops sending dish text and the banner is never shown
  /// twice.
  Future<void> declineDisclosure() => _update(
    _appSettings.copyWith(estimationConsentGiven: false, disclosureSeen: true),
  );

  /// Records that the first-run restriction onboarding has been completed
  /// or skipped (ALG-02b), so it is never shown twice. Touches nothing but
  /// that flag; a no-op, with no write, when it is already set.
  Future<void> markOnboardingSeen() async {
    if (onboardingSeen) return;
    await _update(_appSettings.copyWith(onboardingSeen: true));
  }

  /// Turns sharing what the staff told the user on or off (ALG-14, issue
  /// #409). A no-op, with no write, when it is already so. Named rather
  /// than positional for the reason [setConsent] gives.
  Future<void> setShareConfirmations({required bool enabled}) async {
    if (enabled == shareConfirmations) return;
    await _update(_appSettings.copyWith(shareConfirmations: enabled));
  }

  /// Records that the helper-tool sheet has been shown (ALG-11), so it is
  /// never shown twice. A no-op, with no write, when it is already set.
  Future<void> markHelperToolSeen() async {
    if (helperToolSeen) return;
    await _update(_appSettings.copyWith(helperToolSeen: true));
  }

  /// Adds [id] to the profile, last, with no exceptions (issue #344).
  ///
  /// A no-op, with no write, when the profile already holds [id], so a
  /// double tap cannot reset its exceptions.
  Future<void> addRestriction(RestrictionId id) async {
    if (profile.contains(id)) return;
    await _update(_appSettings.copyWith(profile: profile.withEntry(id)));
  }

  /// Makes the profile hold exactly [ids] besides keto and the user's own
  /// words, for the setup run again from Settings (issue #421): an id the
  /// profile holds keeps its place and its exceptions, one it does not is
  /// added last, and an entry not in [ids] is removed. The keto entry and
  /// the user's own words are not on the setup screen and are left alone.
  /// A no-op, with no write, when nothing would change.
  Future<void> replaceRestrictions(List<RestrictionId> ids) async {
    var next = profile;
    for (final entry in profile.entries) {
      final id = entry.restrictionId;
      if (id == RestrictionId.keto || id == RestrictionId.custom) continue;
      if (!ids.contains(id)) next = next.withoutEntry(id);
    }
    for (final id in ids) {
      if (id != RestrictionId.keto && id != RestrictionId.custom) {
        next = next.withEntry(id);
      }
    }
    if (next == profile) return;
    await _update(_appSettings.copyWith(profile: next));
  }

  /// Removes [id] and its exceptions from the profile (issue #344). A
  /// no-op, with no write, when the profile does not hold [id].
  Future<void> removeRestriction(RestrictionId id) async {
    if (!profile.contains(id)) return;
    await _update(_appSettings.copyWith(profile: profile.withoutEntry(id)));
  }

  /// Adds [term], one of the user's own words, to their own restriction
  /// (ALG-17), adding that entry last when it is absent. A no-op, with no
  /// write, when [term] is blank, already held (ignoring case) or the entry
  /// is full ([DietaryProfile.withCustomTerm]).
  Future<void> addCustomTerm(String term) async {
    final next = profile.withCustomTerm(term);
    if (identical(next, profile)) return;
    await _update(_appSettings.copyWith(profile: next));
  }

  /// Removes [term] from the user's own restriction, and the entry with its
  /// last word (ALG-17). A no-op, with no write, when it is not held.
  Future<void> removeCustomTerm(String term) async {
    final next = profile.withoutCustomTerm(term);
    if (identical(next, profile)) return;
    await _update(_appSettings.copyWith(profile: next));
  }

  /// Replaces the exceptions of [id] with [exceptions], trimmed,
  /// de-duplicated and capped ([ProfileEntry.normaliseExceptions]; issue
  /// #344). A no-op, with no write, when the profile does not hold [id]:
  /// setting exceptions never adds a restriction by the back door.
  Future<void> setExceptions(RestrictionId id, List<String> exceptions) async {
    if (!profile.contains(id)) return;
    await _update(
      _appSettings.copyWith(
        profile: profile.withEntry(id, exceptions: exceptions),
      ),
    );
  }

  /// Every profile on this device, the user's own first (Banto, ALG-12,
  /// issue #354).
  List<NamedProfile> get profiles => _appSettings.profiles;

  /// The profile [id], or null when there is none.
  NamedProfile? profileById(String id) {
    for (final named in profiles) {
      if (named.id == id) return named;
    }
    return null;
  }

  /// The profiles a menu is read for (ALG-12); the user's own alone until
  /// others are combined.
  List<NamedProfile> get activeProfiles => _appSettings.activeProfiles;

  /// Whether another profile can be added: fewer than
  /// [NamedProfile.maxProfiles] are kept.
  bool get canAddProfile => profiles.length < NamedProfile.maxProfiles;

  /// Adds a person called [name] holding [profile], last, and answers the
  /// new id (ALG-12). A no-op answering null, with no write, when the name
  /// is blank or [canAddProfile] is false. The new person is not combined
  /// into menus until the user selects them.
  ///
  /// Ids are `p1`, `p2`, … — the first number no profile uses — so the
  /// same steps always give the same id, with no clock and no randomness.
  Future<String?> addProfile(
    String name, {
    DietaryProfile profile = DietaryProfile.empty,
  }) async {
    final normalised = NamedProfile.normaliseName(name);
    if (normalised.isEmpty || !canAddProfile) return null;
    final used = <String>{for (final named in profiles) named.id};
    var n = 1;
    while (used.contains('p$n')) {
      n++;
    }
    final id = 'p$n';
    await _update(
      _appSettings.copyWith(
        otherProfiles: List<NamedProfile>.unmodifiable(<NamedProfile>[
          ..._appSettings.otherProfiles,
          NamedProfile(id: id, name: normalised, profile: profile),
        ]),
      ),
    );
    return id;
  }

  /// Renames [id] to [name], normalised ([NamedProfile.normaliseName]). A
  /// blank name is refused for another person and, for the user's own
  /// profile, restores the default "Me". A no-op for an unknown [id].
  Future<void> renameProfile(String id, String name) async {
    final normalised = NamedProfile.normaliseName(name);
    if (id == NamedProfile.primaryId) {
      if (normalised == _appSettings.primaryProfileName) return;
      await _update(_appSettings.copyWith(primaryProfileName: normalised));
      return;
    }
    if (normalised.isEmpty) return;
    await _replaceOther(id, (named) => named.copyWith(name: normalised));
  }

  /// Removes the person [id] and their restrictions from this device, and
  /// from the profiles menus are read for (ALG-12). The user's own profile
  /// cannot be deleted; a no-op for it and for an unknown [id].
  Future<void> deleteProfile(String id) async {
    if (id == NamedProfile.primaryId || profileById(id) == null) return;
    final active = <String>[
      for (final activeId in _appSettings.activeProfileIds)
        if (activeId != id) activeId,
    ];
    await _update(
      _appSettings.copyWith(
        otherProfiles: List<NamedProfile>.unmodifiable(<NamedProfile>[
          for (final named in _appSettings.otherProfiles)
            if (named.id != id) named,
        ]),
        activeProfileIds: active.isEmpty
            ? AppSettings.defaultActiveProfileIds
            : List<String>.unmodifiable(active),
      ),
    );
  }

  /// Adds [restriction] to the profile [id] (ALG-12); for the user's own,
  /// exactly [addRestriction]. A no-op when it is already held.
  Future<void> addRestrictionTo(String id, RestrictionId restriction) async {
    if (id == NamedProfile.primaryId) {
      await addRestriction(restriction);
      return;
    }
    final named = profileById(id);
    if (named == null || named.profile.contains(restriction)) return;
    await _replaceOther(
      id,
      (named) => named.copyWith(profile: named.profile.withEntry(restriction)),
    );
  }

  /// Removes [restriction] from the profile [id] (ALG-12); for the user's
  /// own, exactly [removeRestriction]. A no-op when it is not held.
  Future<void> removeRestrictionFrom(
    String id,
    RestrictionId restriction,
  ) async {
    if (id == NamedProfile.primaryId) {
      await removeRestriction(restriction);
      return;
    }
    final named = profileById(id);
    if (named == null || !named.profile.contains(restriction)) return;
    await _replaceOther(
      id,
      (named) =>
          named.copyWith(profile: named.profile.withoutEntry(restriction)),
    );
  }

  /// Replaces the exceptions of [restriction] in the profile [id] (#417);
  /// for the user's own, exactly [setExceptions]. A no-op, with no write,
  /// when [id] is unknown or the profile does not hold [restriction].
  Future<void> setExceptionsFor(
    String id,
    RestrictionId restriction,
    List<String> exceptions,
  ) async {
    if (id == NamedProfile.primaryId) {
      await setExceptions(restriction, exceptions);
      return;
    }
    final named = profileById(id);
    if (named == null || !named.profile.contains(restriction)) return;
    await _replaceOther(
      id,
      (named) => named.copyWith(
        profile: named.profile.withEntry(restriction, exceptions: exceptions),
      ),
    );
  }

  /// Adds [term] to the own restriction of the profile [id] (ALG-17); for
  /// the user's own profile, exactly [addCustomTerm]. A no-op when nothing
  /// would change or [id] is unknown.
  Future<void> addCustomTermTo(String id, String term) async {
    if (id == NamedProfile.primaryId) {
      await addCustomTerm(term);
      return;
    }
    final named = profileById(id);
    if (named == null) return;
    final next = named.profile.withCustomTerm(term);
    if (identical(next, named.profile)) return;
    await _replaceOther(id, (named) => named.copyWith(profile: next));
  }

  /// Removes [term] from the own restriction of the profile [id] (ALG-17);
  /// for the user's own profile, exactly [removeCustomTerm]. A no-op when
  /// it is not held or [id] is unknown.
  Future<void> removeCustomTermFrom(String id, String term) async {
    if (id == NamedProfile.primaryId) {
      await removeCustomTerm(term);
      return;
    }
    final named = profileById(id);
    if (named == null) return;
    final next = named.profile.withoutCustomTerm(term);
    if (identical(next, named.profile)) return;
    await _replaceOther(id, (named) => named.copyWith(profile: next));
  }

  /// Sets which profiles menus are read for to [ids], in [profiles]'
  /// order (ALG-12). Unknown ids are dropped; an empty result is refused,
  /// since a menu is always read for someone.
  Future<void> setActiveProfiles(Iterable<String> ids) async {
    final wanted = ids.toSet();
    final next = <String>[
      for (final named in profiles)
        if (wanted.contains(named.id)) named.id,
    ];
    if (next.isEmpty) return;
    await _update(
      _appSettings.copyWith(activeProfileIds: List<String>.unmodifiable(next)),
    );
  }

  /// Where the user is travelling (Banto, ALG-13, issue #355), or null
  /// when trip mode is off. Kept on this device only, like the profile.
  TripDestination? get tripDestination => _appSettings.tripDestination;

  /// Starts trip mode for [destination], or switches it off with null
  /// (ALG-13: one tap). A no-op, with no write, when it is already so.
  /// Changes nothing about keto and nothing the next request carries: the
  /// destination's lexicon is read on the device only.
  Future<void> setTripDestination(TripDestination? destination) async {
    if (destination == tripDestination) return;
    await _update(_appSettings.copyWith(tripDestination: destination));
  }

  /// Replaces the other person [id] with what [change] makes of it.
  Future<void> _replaceOther(
    String id,
    NamedProfile Function(NamedProfile named) change,
  ) => _update(
    _appSettings.copyWith(
      otherProfiles: List<NamedProfile>.unmodifiable(<NamedProfile>[
        for (final named in _appSettings.otherProfiles)
          if (named.id == id) change(named) else named,
      ]),
    ),
  );

  /// Replaces the held settings with [next] and persists them, marking
  /// [isBusy] around the write exactly as every other setter here does.
  Future<void> _update(AppSettings next) async {
    _isBusy = true;
    notifyListeners();

    _appSettings = next;
    await _settings.write(_appSettings);

    _isBusy = false;
    notifyListeners();
  }

  /// Forgets every cached menu and analysis, through the repository, and
  /// empties the Recent list (the visit history, D23, issue #314), then
  /// re-reads [cachedMenuCount] so the Settings screen's count reflects
  /// the clear immediately, without a second [load] call. Also clears the
  /// last-opened venue and last-used filter (issue #55) — a stale
  /// [AppSettings.lastVenue] would otherwise offer to resume a venue whose
  /// cached menu this call just removed.
  Future<void> clearCache() async {
    _isBusy = true;
    notifyListeners();

    await _repository.clearCache();
    await _history.clear();
    _cachedMenuCount = await _repository.cachedMenuCount();
    _appSettings = _appSettings.copyWith(lastVenue: null, lastFilter: null);
    await _settings.write(_appSettings);

    _isBusy = false;
    notifyListeners();
  }
}
