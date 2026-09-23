import 'package:ketoclub/services/storage/install_id_store.dart';

/// A fixed, valid 32-character lowercase hex ID, used as
/// [FakeInstallIdStore]'s default so a test that does not care about the
/// exact value still gets one shaped like a real install ID.
const String _defaultFakeInstallId = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// An [InstallIdStore] that always answers with the same, given ID.
final class FakeInstallIdStore implements InstallIdStore {
  /// Creates a store that answers [id] with [installId], or with a fixed
  /// default 32-hex ID when omitted.
  // ignore: prefer_initializing_formals
  new({String installId = _defaultFakeInstallId}) : _installId = installId;

  final String _installId;

  /// How many times [id] has been called.
  int calls = 0;

  @override
  Future<String> id() async {
    calls++;
    return _installId;
  }
}
