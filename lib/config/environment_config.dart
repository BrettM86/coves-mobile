import 'dart:io';

import 'package:flutter/foundation.dart';

/// Environment Configuration for Coves Mobile
///
/// Supports multiple environments:
/// - Production: Coves production server (prod flavor)
/// - Local: Local PDS + PLC for development/testing (dev flavor)
/// - Test: Closed loopback port, selected under host-side `flutter test`
///
/// Environment is determined by (in priority order):
/// 1. --dart-define=ENVIRONMENT=local/production (explicit override)
/// 2. --dart-define=ENV=dev/local/prod/production (shorthand override)
/// 3. Flutter flavor (dev -> local, prod -> production)
/// 4. Under host-side `flutter test` (flutter_tester sets FLUTTER_TEST) in a
///    non-release build: test. On-device integration_test runs do not set
///    FLUTTER_TEST and need an explicit define.
/// 5. Otherwise: production
///
/// An empty value falls through to the next priority. A non-empty value that
/// is not in the accepted list for its input throws a [StateError], so a typo
/// such as ENVIRONMENT=dev cannot silently select production.
enum Environment { production, local, test }

class EnvironmentConfig {
  const EnvironmentConfig({
    required this.environment,
    required this.apiUrl,
    required this.webUrl,
    required this.handleResolverUrl,
    required this.plcDirectoryUrl,
  });
  final Environment environment;
  final String apiUrl;

  /// Origin of the web client, used to build shareable links. This is the
  /// address a link recipient opens in a browser, not an endpoint this app
  /// calls, so it can differ from [apiUrl].
  final String webUrl;
  final String handleResolverUrl;
  final String plcDirectoryUrl;

  /// Production configuration, selected when no define, flavor or test
  /// runner applies.
  /// Uses Coves production server with public atproto infrastructure
  static const production = EnvironmentConfig(
    environment: Environment.production,
    apiUrl: 'https://coves.social',
    webUrl: 'https://coves.social',
    handleResolverUrl:
        'https://bsky.social/xrpc/com.atproto.identity.resolveHandle',
    plcDirectoryUrl: 'https://plc.directory',
  );

  /// Local development configuration
  /// Uses localhost via adb reverse port forwarding through Caddy proxy
  ///
  /// IMPORTANT: Before testing, run `make mobile-setup` in the Coves backend,
  /// or manually forward ports:
  ///   adb reverse tcp:3001 tcp:3001  # PDS
  ///   adb reverse tcp:3002 tcp:3002  # PLC
  ///   adb reverse tcp:8080 tcp:8080  # Caddy proxy (OAuth callbacks)
  ///   adb reverse tcp:8081 tcp:8081  # AppView
  ///
  /// Note: `adb reverse` is Android-only. iOS Simulator connects to
  /// localhost directly without port forwarding.
  ///
  /// Note: For physical devices not connected via USB, use ngrok URLs instead
  ///
  /// Note: webUrl uses 127.0.0.1 where apiUrl uses localhost, even though both
  /// reach the same Caddy proxy. The local frontend canonicalises itself to
  /// 127.0.0.1 so OAuth cookies are scoped to a single host, and a shared link
  /// that opens on the other spelling lands on a signed-out session.
  static const local = EnvironmentConfig(
    environment: Environment.local,
    apiUrl: 'http://localhost:8080',
    webUrl: 'http://127.0.0.1:8080',
    handleResolverUrl:
        'http://localhost:3001/xrpc/com.atproto.identity.resolveHandle',
    plcDirectoryUrl: 'http://localhost:3002',
  );

  /// Host-side `flutter test` configuration
  ///
  /// Every requested endpoint points at port 1 on loopback, a closed port
  /// that refuses connections immediately. Under testWidgets the test
  /// binding's HttpOverrides answers every request with a synthetic 400
  /// first; the loopback port is the backstop for plain test(), where a
  /// network call the test forgot to mock fails fast with a connection error
  /// instead of reaching production. webUrl stays the public origin because
  /// it is only used to build share links and is never requested.
  static const test = EnvironmentConfig(
    environment: Environment.test,
    apiUrl: 'http://127.0.0.1:1',
    webUrl: 'https://coves.social',
    handleResolverUrl:
        'http://127.0.0.1:1/xrpc/com.atproto.identity.resolveHandle',
    plcDirectoryUrl: 'http://127.0.0.1:1',
  );

  /// Resolves the environment from build defines and the process
  /// environment, following the priority order and unrecognized-value rule
  /// documented on [Environment].
  ///
  /// Throws a [StateError] naming the input and its accepted values when a
  /// non-empty value is not recognized.
  @visibleForTesting
  static EnvironmentConfig resolve({
    required String environmentOverride,
    required String environmentShorthand,
    required String flavor,
    required bool isFlutterTest,
  }) {
    // Priority 1: Explicit environment override
    switch (environmentOverride) {
      case '':
        break;
      case 'local':
        return local;
      case 'production':
        return production;
      default:
        throw StateError(
          'Unrecognized --dart-define=ENVIRONMENT=$environmentOverride; '
          'accepted values: local, production',
        );
    }

    // Priority 2: Shorthand ENV override (dev -> local, prod -> production)
    switch (environmentShorthand) {
      case '':
        break;
      case 'dev':
      case 'local':
        return local;
      case 'prod':
      case 'production':
        return production;
      default:
        throw StateError(
          'Unrecognized --dart-define=ENV=$environmentShorthand; '
          'accepted values: dev, local, prod, production',
        );
    }

    // Priority 3: Flavor-based environment
    switch (flavor) {
      case '':
        break;
      case 'dev':
        return local;
      case 'prod':
        return production;
      default:
        throw StateError(
          'Unrecognized --flavor $flavor (FLUTTER_APP_FLAVOR); '
          'accepted values: dev, prod',
        );
    }

    // Priority 4: Flutter test runner
    if (isFlutterTest) {
      return test;
    }

    // Default: production
    return production;
  }

  /// Flutter flavor passed via --flavor flag
  /// FLUTTER_APP_FLAVOR is the define the Flutter build system actually
  /// injects for --flavor builds (there is no FLUTTER_FLAVOR define -
  /// reading that name falls through to the default).
  static const String _flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  /// Explicit environment override via --dart-define=ENVIRONMENT=local
  /// Also supports --dart-define=ENV=dev for convenience
  static const String _envOverride = String.fromEnvironment('ENVIRONMENT');
  static const String _envShorthand = String.fromEnvironment('ENV');

  /// Current environment from build defines and the process environment.
  /// See [resolve] and [Environment] for the priority order.
  ///
  /// Computed once: every input is fixed for the life of the process, and
  /// this is read on every Dio construction.
  static final EnvironmentConfig current = resolve(
    environmentOverride: _envOverride,
    environmentShorthand: _envShorthand,
    flavor: _flavor,
    // A release build can never select the test config, even if the
    // process environment happens to contain FLUTTER_TEST.
    isFlutterTest:
        !kReleaseMode && Platform.environment.containsKey('FLUTTER_TEST'),
  );

  /// Get the current flavor name for display purposes
  static String get flavorName {
    if (_flavor.isNotEmpty) {
      return _flavor;
    }
    if (_envOverride == 'local') {
      return 'dev';
    }
    return 'prod';
  }

  bool get isProduction => environment == Environment.production;
  bool get isLocal => environment == Environment.local;
}
