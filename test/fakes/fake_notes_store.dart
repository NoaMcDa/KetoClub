import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/notes_store.dart';

/// A [NotesStore] backed by an in-memory map, keyed by [VenueRef.cacheKey]
/// then dish id.
final class FakeNotesStore implements NotesStore {
  final Map<String, Map<String, String>> _notes =
      <String, Map<String, String>>{};

  /// Every `(ref, dishId, note)` call to [write], in call order.
  final List<({VenueRef ref, String dishId, String note})> writeCalls =
      <({VenueRef ref, String dishId, String note})>[];

  /// Every `(ref, dishId)` call to [delete], in call order.
  final List<({VenueRef ref, String dishId})> deleteCalls =
      <({VenueRef ref, String dishId})>[];

  @override
  Future<String?> read(VenueRef ref, String dishId) async =>
      _notes[ref.cacheKey]?[dishId];

  @override
  Future<void> write(VenueRef ref, String dishId, String note) async {
    writeCalls.add((ref: ref, dishId: dishId, note: note));
    (_notes[ref.cacheKey] ??= <String, String>{})[dishId] = note;
  }

  @override
  Future<void> delete(VenueRef ref, String dishId) async {
    deleteCalls.add((ref: ref, dishId: dishId));
    _notes[ref.cacheKey]?.remove(dishId);
  }

  @override
  Future<Map<String, String>> readAll(VenueRef ref) async =>
      Map<String, String>.from(
        _notes[ref.cacheKey] ?? const <String, String>{},
      );
}
