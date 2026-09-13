import 'package:ketoclub/services/storage/key_store.dart';

/// A [KeyStore] backed by an in-memory field.
final class FakeKeyStore implements KeyStore {
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
