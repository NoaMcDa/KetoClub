/// Why these implementations catch `Exception` rather than naming
/// `PlatformException` and `MissingPluginException`: those types live in
/// `package:flutter/services.dart`, and `services/` may import nothing from
/// Flutter beyond `foundation.dart` (architecture.md §5, enforced by
/// `test/architecture/import_rules_test.dart`). Both implement `Exception`,
/// and each method below promises never to throw across its boundary, so the
/// broad clause states the contract rather than widening it.
library;

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Where the anonymous install ID lives on-device (architecture.md D8,
/// `backend_plan.md` §3.4).
///
/// The ID is random, generated once per install, and never linked to a
/// person: no account, no login, nothing else about the device or its
/// owner is derived from or stored alongside it. It exists only so the
/// backend (#102) can rate-limit and de-duplicate one-vote-per-install
/// writes; it is deliberately spoofable and carries no identity claim.
///
/// Interface only: `di.dart` is the only file that constructs a concrete
/// implementation. Nothing here — and nothing past this seam — ever sends
/// the ID anywhere but the `X-KetoClub-Install-Id` header (#102).
abstract interface class InstallIdStore {
  /// The install's ID: 32 lowercase hex characters.
  ///
  /// Generates and persists one on first call if none is stored yet, or if
  /// the stored value is not a valid ID. Stable across calls on one
  /// instance, and across instances that share the same backing
  /// preferences. Never throws: a storage failure yields a fresh,
  /// unpersisted ID rather than an error.
  Future<String> id();
}

/// The shared_preferences key the install ID is stored under.
const String _installIdStorageKey = 'ketoclub_install_id';

/// How many random bytes make up an install ID, hex-encoded to 32
/// characters (`backend_plan.md` §3.4).
const int _installIdByteLength = 16;

/// Matches exactly the shape [PrefsInstallIdStore] writes: 32 lowercase
/// hex characters. Anything else stored under [_installIdStorageKey] is
/// treated as corrupt and replaced.
final RegExp _validInstallId = RegExp(r'^[0-9a-f]{32}$');

/// An [InstallIdStore] over `shared_preferences`.
///
/// The loader passed to the constructor — `SharedPreferences.getInstance`
/// in `di.dart`, a test double elsewhere — is invoked lazily and at most
/// once: `di.dart` must not perform plugin I/O while building the
/// dependency graph, so the resolved instance is memoised the same way
/// `PrefsSettingsStore` memoises it.
final class PrefsInstallIdStore implements InstallIdStore {
  /// Creates a store whose backing preferences are obtained by calling
  /// [load] on first use.
  new({required this.load});

  /// Loads (or opens) the backing preferences. Invoked at most once; see
  /// [_preferences].
  final Future<SharedPreferences> Function() load;

  /// The preferences, once loaded. Holds the in-flight (or completed)
  /// future rather than a `SharedPreferences` directly, so nothing here
  /// touches preferences before [load] has actually run.
  Future<SharedPreferences>? _prefs;

  /// Returns the preferences, loading them via [load] on the first call
  /// and reusing that result on every later call.
  Future<SharedPreferences> _preferences() => _prefs ??= load();

  @override
  Future<String> id() async {
    final SharedPreferences prefs;
    try {
      prefs = await _preferences();
      // A broken loader still answers with a usable, if unpersisted, ID
      // (mirrors PrefsSettingsStore.read's degrade-to-default).
    } on Exception {
      return _generate();
    }
    final stored = prefs.getString(_installIdStorageKey);
    if (stored != null && _validInstallId.hasMatch(stored)) return stored;
    final generated = _generate();
    try {
      await prefs.setString(_installIdStorageKey, generated);
      // Drop the write; a broken channel degrades to an unpersisted ID
      // rather than throwing.
    } on Exception {
      // Nothing to do: the write above never landed, but the freshly
      // generated ID is still valid to hand back for this call.
    }
    return generated;
  }

  /// Generates a fresh install ID: [_installIdByteLength] random bytes
  /// from [Random.secure], hex-encoded to lowercase.
  String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      _installIdByteLength,
      (_) => random.nextInt(256),
    );
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
