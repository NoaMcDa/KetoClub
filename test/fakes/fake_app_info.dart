import 'package:ketoclub/services/platform/app_info.dart';

/// An [AppInfo] that answers a scripted version and counts its reads,
/// never touching a real platform channel.
final class FakeAppInfo implements AppInfo {
  /// Creates a fake answering [answer].
  new({this.answer = const AppVersion(version: '1.2.3', buildNumber: '45')});

  /// What [load] answers; null models a platform that cannot say.
  AppVersion? answer;

  /// How many times [load] was called.
  int loadCalls = 0;

  @override
  Future<AppVersion?> load() async {
    loadCalls++;
    return answer;
  }
}
