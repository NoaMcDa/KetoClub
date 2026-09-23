import 'package:ketoclub/services/platform/menu_sharer.dart';

/// A [MenuSharer] that records every call, for a test to assert on, and
/// never touches a real platform channel.
final class FakeMenuSharer implements MenuSharer {
  /// Every call [shareText] received, in call order.
  final List<({String text, String? subject})> shareCalls =
      <({String text, String? subject})>[];

  /// What [shareText] answers. Defaults to `true`, matching a completed
  /// share.
  bool answer = true;

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    shareCalls.add((text: text, subject: subject));
    return answer;
  }
}
