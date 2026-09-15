import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:ketoclub/services/storage/settings_store.dart';

/// The app-wide UI locale, kept in sync with the language tag persisted by
/// `SettingsController` (architecture.md §12, issue #8).
///
/// `MaterialApp` needs one listenable that tells it which [Locale] to use,
/// or null to follow the device locale. Before this class existed nothing
/// filled that role: `SettingsController.setLanguage` wrote a `languageTag`
/// into `AppSettings` and nothing ever read it back, so choosing Hebrew in
/// Settings changed a stored value and nothing else.
///
/// **`SettingsController` stays the only writer of the stored tag.** This
/// class only reads [_settingsStore], once at startup in [load]; it never
/// calls [SettingsStore.write] itself. The one place the two meet is
/// `SettingsScreen`, which calls [applyTag] immediately after a
/// `SettingsController.setLanguage` write completes, so this controller's
/// idea of "current" is always downstream of the single write path rather
/// than a second one racing it — two independent writers over the same
/// on-disk `AppSettings` blob is the split brain the class doc of
/// `SettingsController` warns against, and this design has exactly one.
final class LocaleController extends ChangeNotifier {
  /// Creates a controller that reads [_settingsStore] lazily.
  ///
  /// The store is not touched here, only stored: `di.dart` — and any
  /// `initState` that constructs this before the first frame — must not
  /// perform plugin I/O while building the object graph
  /// (`test/di_test.dart`), so the actual read happens inside [load].
  new(this._settingsStore);

  final SettingsStore _settingsStore;

  Locale? _locale;

  /// The locale `MaterialApp.locale` should use, or null to fall back to
  /// `MaterialApp`'s own device-locale resolution.
  Locale? get locale => _locale;

  /// Reads the persisted language tag once and applies it.
  ///
  /// Called from `KetoClubApp`'s `initState`. The first frame renders in
  /// the device locale — this has not resolved yet — and the UI flips to
  /// the stored language once it does; that one-frame lag is an accepted
  /// trade-off (see issue #8's notes) rather than a bug.
  Future<void> load() async {
    final settings = await _settingsStore.read();
    applyTag(settings.languageTag);
  }

  /// Sets the current locale from a BCP-47 [tag], or clears it — meaning
  /// "follow the device locale" — when [tag] is null.
  ///
  /// Purely in-memory: this never reaches [_settingsStore]. Call it only
  /// after the corresponding write through `SettingsController.setLanguage`
  /// has already completed, so this controller's state never gets ahead of
  /// what is actually persisted on disk.
  void applyTag(String? tag) {
    final next = tag == null ? null : Locale(tag);
    if (next == _locale) return;
    _locale = next;
    notifyListeners();
  }
}
