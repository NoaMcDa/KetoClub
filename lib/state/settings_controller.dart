import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

/// Screen state for the Settings screen (architecture.md §6.6).
///
/// Reads and writes the OpenRouter key through a [KeyStore], the user's
/// preferences through a [SettingsStore], and delegates cache clearing to
/// a [MenuRepository]. **Never exposes the key itself** — only [hasKey],
/// a presence flag — because architecture.md §11 says the key is read
/// solely by `OpenRouterClient` and is never logged, never in a failure
/// value, and never in the cache; a getter that returned it, or a field
/// that outlived [saveKey], would be a way around that rule.
///
/// Never throws — every service behind it already returns values instead
/// of throwing, or promises not to (architecture.md §18.1).
final class SettingsController extends ChangeNotifier {
  /// Creates a controller over a [KeyStore], a [SettingsStore], and a
  /// [MenuRepository].
  ///
  /// The three services are positional and private, matching
  /// `MenuController`: private because a widget reaches a service only
  /// through a controller's own API (architecture.md §5) and a public
  /// field would hand it a way around this class; positional, because a
  /// private field cannot be a named initializing formal in Dart and the
  /// alternative was suppressing a lint on every field. The distinct
  /// types mean a misordered call does not compile.
  new(this._keyStore, this._settings, this._repository);

  final KeyStore _keyStore;
  final SettingsStore _settings;
  final MenuRepository _repository;

  bool _isBusy = false;
  bool _hasKey = false;
  AppSettings _appSettings = const AppSettings();

  /// Whether an operation is currently reading from or writing to a
  /// store.
  bool get isBusy => _isBusy;

  /// Whether an OpenRouter key is currently stored.
  ///
  /// Never the key itself — see the class doc.
  bool get hasKey => _hasKey;

  /// Whether the user has agreed to AI-estimated net-carb figures.
  bool get consentGiven => _appSettings.estimationConsentGiven;

  /// The UI language, as a BCP-47 tag, or null to follow the device
  /// locale.
  String? get languageTag => _appSettings.languageTag;

  /// Which verdicts the menu view keeps by default.
  MenuFilter get filter => _appSettings.filter;

  /// Reads [KeyStore.hasKey] and the [SettingsStore], populating every
  /// other getter.
  Future<void> load() async {
    _isBusy = true;
    notifyListeners();

    final storedHasKey = await _keyStore.hasKey();
    final storedSettings = await _settings.read();

    _hasKey = storedHasKey;
    _appSettings = storedSettings;

    _isBusy = false;
    notifyListeners();
  }

  /// Saves [key] as the OpenRouter key, after trimming it.
  ///
  /// A key that is empty or made only of whitespace is **not written**:
  /// `OpenRouterClient` would reject it regardless, so storing it would
  /// only replace "no key" with a value guaranteed to fail. This is a
  /// silent no-op — [hasKey] keeps whatever value it already had, and no
  /// key is deleted — rather than an error, since the caller learns the
  /// same thing either way by reading [hasKey] afterwards.
  Future<void> saveKey(String key) async {
    _isBusy = true;
    notifyListeners();

    final trimmed = key.trim();
    if (trimmed.isNotEmpty) {
      await _keyStore.write(trimmed);
      _hasKey = true;
    }

    _isBusy = false;
    notifyListeners();
  }

  /// Removes the stored OpenRouter key, if any.
  Future<void> deleteKey() async {
    _isBusy = true;
    notifyListeners();

    await _keyStore.delete();
    _hasKey = false;

    _isBusy = false;
    notifyListeners();
  }

  /// Records whether the user agrees to the disclosure in Settings that dish
  /// text is sent to OpenRouter for analysis (architecture.md §11).
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

  /// Forgets every cached menu and analysis, through the repository.
  Future<void> clearCache() async {
    _isBusy = true;
    notifyListeners();

    await _repository.clearCache();

    _isBusy = false;
    notifyListeners();
  }
}
