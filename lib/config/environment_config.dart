/// Environment Configuration for Coves Mobile
///
/// Supports multiple environments:
/// - Production: Real Bluesky infrastructure
/// - Local: Local PDS + PLC for development/testing
///
/// Set via ENVIRONMENT environment variable or flutter run --dart-define
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
  /// Uses real Bluesky infrastructure
  static const production = EnvironmentConfig(
    environment: Environment.production,
    apiUrl: 'https://coves.social', // TODO: Update when production is live
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

  /// Get current environment based on build configuration
  static EnvironmentConfig get current {
    // Read from --dart-define=ENVIRONMENT=local
    const envString = String.fromEnvironment(
      'ENVIRONMENT',
      defaultValue: 'production',
    );

    switch (envString) {
      case 'local':
        return local;
      case 'production':
      default:
        return production;
    }
  }

  bool get isProduction => environment == Environment.production;
  bool get isLocal => environment == Environment.local;
}
