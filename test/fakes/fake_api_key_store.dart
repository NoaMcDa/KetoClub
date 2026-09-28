import 'package:ketoclub/services/storage/api_key_store.dart';

/// An [ApiKeyStore] backed by an in-memory field.
final class FakeApiKeyStore implements ApiKeyStore {
  /// Creates a store holding [seed], or empty when omitted.
  new({String? seed}) : _key = seed;

  String? _key;

  /// How many times [write] has been called.
  int writeCallCount = 0;

  /// How many times [delete] has been called.
  int deleteCallCount = 0;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String key) async {
    writeCallCount++;
    _key = key;
  }

  @override
  Future<void> delete() async {
    deleteCallCount++;
    _key = null;
  }

  @override
  Future<bool> hasKey() async => _key != null;
}
