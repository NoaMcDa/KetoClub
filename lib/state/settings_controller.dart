import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
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
