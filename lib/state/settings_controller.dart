import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// Screen state for the Settings screen (architecture.md §6.6).
///
/// Reads and writes the user's preferences — including whether dish text
/// may be sent to KetoClub's server for AI analysis — through a
/// [SettingsStore], and delegates cache clearing to a [MenuRepository].
/// There is no credential here: the model key lives on the server.
///
/// Never throws — every service behind it already returns values instead
/// of throwing, or promises not to (architecture.md §18.1).
final class SettingsController extends ChangeNotifier {
  /// Creates a controller over a [SettingsStore] and a [MenuRepository].
  ///
  /// The two services are positional and private, matching
  /// `MenuController`: private because a widget reaches a service only
  /// through a controller's own API (architecture.md §5) and a public
  /// field would hand it a way around this class; positional, because a
  /// private field cannot be a named initializing formal in Dart and the
  /// alternative was suppressing a lint on every field. The distinct
  /// types mean a misordered call does not compile.
  new(this._settings, this._repository);

  final SettingsStore _settings;
  final MenuRepository _repository;

  bool _isBusy = false;
  AppSettings _appSettings = const AppSettings();

  /// Whether an operation is currently reading from or writing to a
  /// store.
  bool get isBusy => _isBusy;

  /// Whether the user has allowed AI analysis: dish text sent to
  /// KetoClub's server, which forwards it to the model provider.
  bool get consentGiven => _appSettings.estimationConsentGiven;

  /// The UI language, as a BCP-47 tag, or null to follow the device
  /// locale.
  String? get languageTag => _appSettings.languageTag;

  /// Which verdicts the menu view keeps by default.
  MenuFilter get filter => _appSettings.filter;

  /// The appearance choice: system, light, or dark (issue #58).
  AppThemeMode get themeMode => _appSettings.themeMode;

  /// The net-carb limit in grams above which no dish is green (issue #57).
  int get netCarbLimitGrams => _appSettings.netCarbLimitGrams;

  /// Reads the [SettingsStore], populating every other getter.
  Future<void> load() async {
    _isBusy = true;
    notifyListeners();

    _appSettings = await _settings.read();

    _isBusy = false;
    notifyListeners();
  }

  /// Records whether the user agrees to the disclosure in Settings that dish
  /// text is sent to KetoClub's server, which forwards it to the model
  /// provider for analysis (architecture.md §11).
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

  /// Forgets every cached menu and analysis, through the repository.
  Future<void> clearCache() async {
    _isBusy = true;
    notifyListeners();

    await _repository.clearCache();

    _isBusy = false;
    notifyListeners();
  }
}
