/// Reads one QR code with the device camera (architecture.md §6.6; issue
/// #182): the Scan tab's "Scan QR code" action.
///
/// [scan] never throws. A denied camera permission, a plugin error and a
/// user who backs out of the camera view all answer null, so "the user
/// changed their mind" and "nothing could be read" look the same to the
/// caller, exactly as with `PagePicker`. What the code says is another
/// class's business: the payload comes back verbatim and
/// `QrPayloadRouter.classify` decides where it goes.
abstract interface class QrScanner {
  /// Whether this build can scan at all. The Scan tab hides its QR action
  /// when this is false (web, where pasting the URL already works).
  bool get isAvailable;

  /// Opens the camera, waits for the first QR code and returns its text, or
  /// null when cancelled, denied or unreadable. Never throws.
  Future<String?> scan();
}

/// The [QrScanner] for a build with no camera scanning (web): unavailable,
/// and every [scan] answers null, as if cancelled, with no plugin I/O. It is
/// also `AppDependencies`'s default, so a test that never scans need not
/// build one.
final class NoQrScanner implements QrScanner {
  /// Creates the scanner; it holds no state.
  const new();

  @override
  bool get isAvailable => false;

  @override
  Future<String?> scan() async => null;
}
