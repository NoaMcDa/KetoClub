/// Where the OpenRouter API key lives on-device (architecture.md §6.4,
/// §11).
///
/// Interface only: `di.dart` is the only file that constructs a concrete
/// implementation (a `flutter_secure_storage`-backed one is Keychain on
/// iOS, Keystore-backed on Android, and browser storage on web). Nothing
/// in `services/` past this seam ever logs the key or sends it anywhere
/// but the OpenRouter client.
abstract interface class KeyStore {
  /// The stored key, or null when none has been saved.
  ///
  /// Never throws: a storage failure reads back the same as "no key".
  Future<String?> read();

  /// Saves [key], replacing any previously stored value.
  ///
  /// Never throws.
  Future<void> write(String key);

  /// Removes the stored key, if any.
  ///
  /// A no-op, not a throw, when no key is stored. Never throws.
  Future<void> delete();

  /// Whether a key is currently stored.
  ///
  /// Never throws.
  Future<bool> hasKey();
}
