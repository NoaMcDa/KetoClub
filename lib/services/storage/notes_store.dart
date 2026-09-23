/// Why this implementation catches `Exception` rather than naming
/// `PlatformException` and `MissingPluginException`: those types live in
/// `package:flutter/services.dart`, and `services/` may import nothing from
/// Flutter beyond `foundation.dart` (architecture.md §5, enforced by
/// `test/architecture/import_rules_test.dart`). Both implement `Exception`,
/// and each method below promises never to throw across its boundary, so the
/// broad clause states the contract rather than widening it.
library;

import 'dart:convert';

import 'package:ketoclub/models/venue.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device storage for a personal note per dish (issue #52,
/// architecture.md D8).
///
/// A note is a short annotation the user writes for themselves — e.g.
/// "Waitstaff happily substituted cauliflower" — never a claim about
/// keto-safety and never part of a verdict. **Notes never leave the
/// device.** They are read only by `MenuController` and rendered only by
/// `DishCard` and the note editor sheet: no note ever reaches
/// `MenuAnalysisPrompt`, a chat request, the menu cache, or a log. That is
/// the point of D8's "nothing about the user is stored" — this is
/// something the user chose to write about a dish, kept entirely local,
/// and this interface is the one seam through which it is read or
/// written, so a future caller cannot smuggle it past that boundary by
/// accident.
///
/// Keyed by [VenueRef] and the dish id within that venue's menu — the
/// same pairing `MenuCache` and `AnalysedDish` already use — so a note
/// survives a menu refetch (the dish id is stable across fetches of the
/// same venue) and is removable per dish without touching any other
/// dish's note.
abstract interface class NotesStore {
  /// The note written for [dishId] on the venue [ref], or null when none
  /// has been written.
  ///
  /// Never throws.
  Future<String?> read(VenueRef ref, String dishId);

  /// Saves [note] for [dishId] on the venue [ref], replacing any note
  /// already there for that dish. Other dishes' notes on [ref], and every
  /// note on any other venue, are left untouched.
  ///
  /// Never throws.
  Future<void> write(VenueRef ref, String dishId, String note);

  /// Removes the note for [dishId] on the venue [ref], if there is one.
  /// A no-op when there is none.
  ///
  /// Never throws.
  Future<void> delete(VenueRef ref, String dishId);

  /// Every note on file for the venue [ref], keyed by dish id, or empty
  /// when none has been written for it.
  ///
  /// Never null. Never throws.
  Future<Map<String, String>> readAll(VenueRef ref);
}

/// The shared_preferences key prefix a venue's notes are stored under, one
/// JSON object per venue mapping dish id to note text.
///
/// Namespaced separately from [VenueRef.cacheKey] (which already includes
/// the platform and its own `/`) so a notes entry can never collide with
/// `PrefsSettingsStore`'s or `PrefsInstallIdStore`'s single-key storage.
String _notesKey(VenueRef ref) => 'ketoclub_notes_${ref.cacheKey}';

/// A [NotesStore] over `shared_preferences`.
///
/// The loader passed to the constructor — `SharedPreferences.getInstance`
/// in `di.dart`, a test double elsewhere — is invoked lazily and at most
/// once: `di.dart` must not perform plugin I/O while building the
/// dependency graph, so the resolved instance is memoised the same way
/// `PrefsSettingsStore` and `PrefsInstallIdStore` memoise it.
final class PrefsNotesStore implements NotesStore {
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

  /// The notes stored for [ref], or empty on any read failure — a broken
  /// store reads back as "no notes yet", never a throw.
  Future<Map<String, String>> _readMap(VenueRef ref) async {
    final SharedPreferences prefs;
    try {
      prefs = await _preferences();
    } on Exception {
      return const <String, String>{};
    }
    final raw = prefs.getString(_notesKey(ref));
    if (raw == null) return const <String, String>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <String, String>{};
    }
    if (decoded is! Map<String, Object?>) return const <String, String>{};
    final notes = <String, String>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is String) notes[entry.key] = value;
    }
    return notes;
  }

  /// Persists [notes] as [ref]'s whole notes map, or removes the key
  /// entirely once it would otherwise be empty, so a venue with no notes
  /// left behind leaves no stray empty object in storage. Drops the write
  /// on any failure rather than throwing.
  Future<void> _writeMap(VenueRef ref, Map<String, String> notes) async {
    final SharedPreferences prefs;
    try {
      prefs = await _preferences();
    } on Exception {
      return;
    }
    try {
      if (notes.isEmpty) {
        await prefs.remove(_notesKey(ref));
      } else {
        await prefs.setString(_notesKey(ref), jsonEncode(notes));
      }
    } on Exception {
      // Nothing to do: the write above never landed.
    }
  }

  @override
  Future<String?> read(VenueRef ref, String dishId) async {
    final notes = await _readMap(ref);
    return notes[dishId];
  }

  @override
  Future<void> write(VenueRef ref, String dishId, String note) async {
    final notes = Map<String, String>.from(await _readMap(ref));
    notes[dishId] = note;
    await _writeMap(ref, notes);
  }

  @override
  Future<void> delete(VenueRef ref, String dishId) async {
    final notes = Map<String, String>.from(await _readMap(ref));
    if (notes.remove(dishId) == null) return;
    await _writeMap(ref, notes);
  }

  @override
  Future<Map<String, String>> readAll(VenueRef ref) => _readMap(ref);
}
