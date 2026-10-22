/// Stand-ins for the `dart:io` exceptions `IOClient` lets through
/// unwrapped (issue #278). `services/` may not import `dart:io`, so the
/// chat clients cannot name `HandshakeException` or `SocketException`:
/// they catch any [Exception]. These prove it with types that are
/// exceptions but not `ClientException`s.
library;

/// A TLS handshake failure: a captive portal, or a wrong device clock.
final class FakeHandshakeException implements Exception {
  /// Creates the stand-in.
  const new();

  @override
  String toString() => 'FakeHandshakeException: CERTIFICATE_VERIFY_FAILED';
}

/// A socket closed while a reply body was being read.
final class FakeSocketException implements Exception {
  /// Creates the stand-in.
  const new();

  @override
  String toString() => 'FakeSocketException: Connection reset by peer';
}
