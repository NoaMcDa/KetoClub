import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:ketoclub/services/storage/settings_store.dart';

/// The app-wide appearance mode, kept in sync with the [AppThemeMode]
/// persisted by `SettingsController` (architecture.md §12's pattern,
/// applied to appearance instead of language; issue #58).
///
/// `MaterialApp` needs one listenable that tells it which [ThemeMode] to
/// use. This class is that listenable, and mirrors `LocaleController`
/// deliberately, down to the split-brain warning below: two independent
/// writers over the same on-disk `AppSettings` blob is exactly the failure
/// mode `LocaleController`'s own class doc names, and this design has
/// exactly one writer here too.
///
/// **`SettingsController` stays the only writer of the stored mode.** This
/// class only reads [_settingsStore], once at startup in [load]; it never
/// calls [SettingsStore.write] itself. The one place the two meet is
/// `SettingsScreen`, which calls [applyMode] immediately after a
/// `SettingsController.setThemeMode` write completes, so this controller's
/// idea of "current" is always downstream of the single write path rather
/// than a second one racing it.
final class ThemeModeController extends ChangeNotifier {
  /// Creates a controller that reads [_settingsStore] lazily.
  ///
  /// The store is not touched here, only stored: `di.dart` — and any
  /// `initState` that constructs this before the first frame — must not
  /// perform plugin I/O while building the object graph
  /// (`test/di_test.dart`), so the actual read happens inside [load].
  new(this._settingsStore);

  final SettingsStore _settingsStore;

  AppThemeMode _mode = AppThemeMode.system;

  /// The persisted appearance choice itself, for a widget that wants to
  /// show the current selection rather than the Flutter-level
  /// [themeMode].
  AppThemeMode get mode => _mode;

  /// The [ThemeMode] `MaterialApp.themeMode` should use, mapped from
  /// [mode]. This mapping lives here, not in `services/storage`, because
  /// `services/` may import nothing from
  /// `package:flutter/material.dart` (architecture.md §5).
  ThemeMode get themeMode => switch (_mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// Reads the persisted appearance mode once and applies it.
  ///
  /// Called from `KetoClubApp`'s `initState`, the same way
  /// `LocaleController.load` is: the first frame renders with
  /// [AppThemeMode.system] — this has not resolved yet — and the theme
  /// flips once it does, mirroring the accepted one-frame lag
  /// `LocaleController` already carries for the locale.
  Future<void> load() async {
    final settings = await _settingsStore.read();
    applyMode(settings.themeMode);
  }

  /// Sets the current appearance mode to [mode].
  ///
  /// Purely in-memory: this never reaches [_settingsStore]. Call it only
  /// after the corresponding write through
  /// `SettingsController.setThemeMode` has already completed, so this
  /// controller's state never gets ahead of what is actually persisted on
  /// disk.
  void applyMode(AppThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }
}
