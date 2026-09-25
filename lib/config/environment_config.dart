/// Environment Configuration for Coves Mobile
///
/// Supports multiple environments:
/// - Production: Real Bluesky infrastructure (prod flavor)
/// - Local: Local PDS + PLC for development/testing (dev flavor)
///
/// Environment is determined by (in priority order):
/// 1. --dart-define=ENVIRONMENT=local/production (explicit override)
/// 2. Flutter flavor (dev -> local, prod -> production)
/// 3. Default: production
enum Environment { production, local }

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

  /// Production configuration (default)
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

  /// Flutter flavor passed via --flavor flag
  /// FLUTTER_APP_FLAVOR is the define the Flutter build system actually
  /// injects for --flavor builds (there is no FLUTTER_FLAVOR define -
  /// reading that name silently falls through to production).
  static const String _flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  /// Explicit environment override via --dart-define=ENVIRONMENT=local
  /// Also supports --dart-define=ENV=dev for convenience
  static const String _envOverride = String.fromEnvironment('ENVIRONMENT');
  static const String _envShorthand = String.fromEnvironment('ENV');

  /// Get current environment based on build configuration
  ///
  /// Priority:
  /// 1. Explicit --dart-define=ENVIRONMENT=local/production
  /// 2. Flavor: dev -> local, prod -> production
  /// 3. Default: production
  static EnvironmentConfig get current {
    // Priority 1: Explicit environment override
    if (_envOverride.isNotEmpty) {
      switch (_envOverride) {
        case 'local':
          return local;
        case 'production':
          return production;
      }
    }

    // Priority 1b: Shorthand ENV override (dev -> local, prod -> production)
    if (_envShorthand.isNotEmpty) {
      switch (_envShorthand) {
        case 'dev':
        case 'local':
          return local;
        case 'prod':
        case 'production':
          return production;
      }
    }

    // Priority 2: Flavor-based environment
    switch (_flavor) {
      case 'dev':
        return local;
      case 'prod':
        return production;
    }

    // Default: production
    return production;
  }

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
