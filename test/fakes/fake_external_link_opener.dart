import 'package:ketoclub/services/platform/external_link_opener.dart';

/// An [ExternalLinkOpener] that records every call, for a test to assert
/// on, and never touches a real platform channel.
final class FakeExternalLinkOpener implements ExternalLinkOpener {
  /// Every URI [open] was called with, in call order.
  final List<Uri> openCalls = <Uri>[];

  /// What [open] answers. Defaults to `true`, matching a working launch.
  bool answer = true;

  @override
  Future<bool> open(Uri uri) async {
    openCalls.add(uri);
    return answer;
  }
}
