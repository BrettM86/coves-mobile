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
    required this.handleResolverUrl,
    required this.plcDirectoryUrl,
  });
  final Environment environment;
  final String apiUrl;
  final String handleResolverUrl;
  final String plcDirectoryUrl;

  /// Production configuration (default)
  /// Uses Coves production server with public atproto infrastructure
  static const production = EnvironmentConfig(
    environment: Environment.production,
    apiUrl: 'https://coves.social',
    handleResolverUrl:
        'https://bsky.social/xrpc/com.atproto.identity.resolveHandle',
    plcDirectoryUrl: 'https://plc.directory',
  );

  /// Local development configuration
  /// Uses localhost via adb reverse port forwarding
  ///
  /// IMPORTANT: Before testing, run these commands to forward ports:
  ///   adb reverse tcp:3001 tcp:3001  # PDS
  ///   adb reverse tcp:3002 tcp:3002  # PLC
  ///   adb reverse tcp:8081 tcp:8081  # AppView
  ///
  /// Note: For physical devices not connected via USB, use ngrok URLs instead
  static const local = EnvironmentConfig(
    environment: Environment.local,
    apiUrl: 'http://localhost:8081',
    handleResolverUrl:
        'http://localhost:3001/xrpc/com.atproto.identity.resolveHandle',
    plcDirectoryUrl: 'http://localhost:3002',
  );

  /// Flutter flavor passed via --flavor flag
  /// This is set automatically by Flutter build system
  static const String _flavor = String.fromEnvironment('FLUTTER_FLAVOR');

  /// Explicit environment override via --dart-define=ENVIRONMENT=local
  static const String _envOverride = String.fromEnvironment('ENVIRONMENT');

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
