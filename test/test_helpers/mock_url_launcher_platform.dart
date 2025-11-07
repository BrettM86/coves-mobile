import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Mock implementation of UrlLauncherPlatform for testing
class MockUrlLauncherPlatform extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];
  PreferredLaunchMode? lastLaunchMode;
  bool canLaunchResponse = true;
  bool launchResponse = true;

  @override
  Future<bool> canLaunch(String url) async {
    return canLaunchResponse;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchedUrls.add(url);
    return launchResponse;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    lastLaunchMode = options.mode;
    return launchResponse;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async {
    return true;
  }

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async {
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
