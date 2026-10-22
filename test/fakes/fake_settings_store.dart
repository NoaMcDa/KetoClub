import 'package:ketoclub/services/storage/settings_store.dart';

/// A [SettingsStore] backed by an in-memory field, defaulting to
/// [AppSettings] defaults like a virgin store.
final class FakeSettingsStore implements SettingsStore {
  /// Creates a store seeded with [initial], or with defaults when
  /// omitted.
  new({AppSettings initial = const AppSettings()}) : _settings = initial;

  AppSettings _settings;

  /// How many times [write] or [update] has been called.
  int writeCallCount = 0;

  @override
  Future<AppSettings> read() async => _settings;

  @override
  Future<void> write(AppSettings settings) async {
    writeCallCount++;
    _settings = settings;
  }

  @override
  Future<AppSettings> update(
    AppSettings Function(AppSettings latest) change,
  ) async {
    writeCallCount++;
    return _settings = change(_settings);
  }
}
