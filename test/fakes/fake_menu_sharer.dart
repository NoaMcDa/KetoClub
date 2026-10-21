import 'dart:typed_data';

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

  /// Every call [shareImage] received, in call order.
  final List<({Uint8List png, String? subject, String? fallbackText})>
  imageCalls = <({Uint8List png, String? subject, String? fallbackText})>[];

  /// Whether this fake platform can share files. When false, [shareImage]
  /// takes the text path, as a browser without file sharing does.
  bool canShareFiles = true;

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    shareCalls.add((text: text, subject: subject));
    return answer;
  }

  @override
  Future<bool> shareImage(
    Uint8List png, {
    String? subject,
    String? fallbackText,
    void Function()? onTextFallback,
  }) async {
    imageCalls.add((png: png, subject: subject, fallbackText: fallbackText));
    if (canShareFiles) return answer;
    if (fallbackText == null) return false;
    onTextFallback?.call();
    return await shareText(fallbackText, subject: subject);
  }
}
