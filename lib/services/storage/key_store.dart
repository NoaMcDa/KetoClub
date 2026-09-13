/// Why these implementations catch `Exception` rather than naming
/// `PlatformException` and `MissingPluginException`: those types live in
/// `package:flutter/services.dart`, and `services/` may import nothing from
/// Flutter beyond `foundation.dart` (architecture.md §5, enforced by
/// `test/architecture/import_rules_test.dart`). Both implement `Exception`,
/// and each method below promises never to throw across its boundary, so the
/// broad clause states the contract rather than widening it.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

/// The storage key the OpenRouter API key is saved under (architecture.md
/// §11). Private to this file: nothing outside ever needs the key's
/// location, and nothing here ever logs it next to the value it names.
const String _openRouterKeyStorageKey = 'openrouter_api_key';

/// A [KeyStore] over [FlutterSecureStorage]: Keychain on iOS,
/// Keystore-backed on Android, browser storage on web (architecture.md
/// §11, §13 — web storage is weaker, and Settings says so).
///
/// The storage passed to the constructor is already built, not yet
/// touched: constructing a `FlutterSecureStorage` is cheap and
/// channel-free, so `di.dart` may do it while assembling the dependency
/// graph. Every plugin call happens only when a member below is actually
/// invoked, never from this constructor.
final class SecureKeyStore implements KeyStore {
  /// Creates a store over the given secure storage.
  ///
  /// Positional and private: this class guards the OpenRouter key, so handing
  /// callers the storage handle would hand them a way around it (§11). Dart
  /// cannot express a private named initializing formal, so the choice was
  /// positional or a suppressed lint — see MenuController for the same call.
  const new(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _openRouterKeyStorageKey);
      // A broken channel reads back as "no key" (architecture.md §11):
      // never a throw, and never a value that could leak the key.
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(String key) async {
    try {
      await _storage.write(key: _openRouterKeyStorageKey, value: key);
      // Drop the write; a broken channel degrades instead of throwing.
    } on Exception {
      // Nothing to do: the write above never landed.
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _openRouterKeyStorageKey);
      // Drop the delete; a broken channel degrades instead of throwing.
    } on Exception {
      // Nothing to do: the delete above never landed.
    }
  }

  @override
  Future<bool> hasKey() async {
    try {
      return await _storage.containsKey(key: _openRouterKeyStorageKey);
      // A broken channel reads as "no key" (architecture.md §11): never a
      // throw, and this never returns the value itself, only presence.
    } on Exception {
      return false;
    }
  }
}
