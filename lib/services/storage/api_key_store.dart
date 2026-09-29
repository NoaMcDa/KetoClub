/// Why these implementations catch `Exception` rather than naming
/// `PlatformException` and `MissingPluginException`: those types live in
/// `package:flutter/services.dart`, and `services/` may import nothing from
/// Flutter beyond `foundation.dart` (architecture.md §5, enforced by
/// `test/architecture/import_rules_test.dart`). Both implement `Exception`,
/// and each method below promises never to throw across its boundary, so the
/// broad clause states the contract rather than widening it.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the user's own Gemini API key lives on an iOS or Android device
/// (architecture.md D17, §11).
///
/// Interface only: `di.dart` is the only file that constructs a concrete
/// implementation, and it builds one only off the web — the web build
/// reaches Gemini through KetoClub's backend and has no key at all
/// (D12). Nothing past this seam ever logs the key or sends it anywhere
/// but `GeminiChatClient`, which sends it to Google alone.
abstract interface class ApiKeyStore {
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
  /// Never throws, and never returns the value itself.
  Future<bool> hasKey();
}

/// The storage key the Gemini API key is saved under. Private to this
/// file: nothing outside ever needs the key's location, and nothing here
/// ever logs it next to the value it names.
const String _geminiKeyStorageKey = 'gemini_api_key';

/// An [ApiKeyStore] over [FlutterSecureStorage]: the Keychain on iOS and
/// Keystore-backed encrypted storage on Android (architecture.md §11).
///
/// Constructing a `FlutterSecureStorage` is cheap and channel-free, so
/// `di.dart` may build this store while assembling the dependency graph.
/// Every plugin call happens only when a member below is actually
/// invoked, never from this constructor.
final class SecureApiKeyStore implements ApiKeyStore {
  /// Creates a store over [_storage], the platform's own secure storage
  /// unless a test passes one — defaulted here, the way
  /// `GeolocatorLocationService` defaults its plugin, so `di.dart` needs
  /// no import of the plugin itself.
  ///
  /// Positional and private: this class guards the key, so handing
  /// callers the storage handle would hand them a way around it (§11).
  /// Dart cannot express a private named initializing formal, so the
  /// choice was positional or a suppressed lint — see `MenuController`
  /// for the same call.
  const new([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _geminiKeyStorageKey);
      // A broken channel reads back as "no key" (architecture.md §11):
      // never a throw, and never a value that could leak the key.
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(String key) async {
    try {
      await _storage.write(key: _geminiKeyStorageKey, value: key);
      // Drop the write; a broken channel degrades instead of throwing.
    } on Exception {
      // Nothing to do: the write above never landed.
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _geminiKeyStorageKey);
      // Drop the delete; a broken channel degrades instead of throwing.
    } on Exception {
      // Nothing to do: the delete above never landed.
    }
  }

  @override
  Future<bool> hasKey() async {
    try {
      return await _storage.containsKey(key: _geminiKeyStorageKey);
      // A broken channel reads as "no key" (architecture.md §11): never a
      // throw, and this never returns the value itself, only presence.
    } on Exception {
      return false;
    }
  }
}
