import 'package:coves_flutter/config/environment_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches [expected] by identity, reporting the environment on mismatch.
Matcher isConfig(EnvironmentConfig expected) => allOf(
  isA<EnvironmentConfig>().having(
    (config) => config.environment,
    'environment',
    expected.environment,
  ),
  same(expected),
);

void main() {
  group('EnvironmentConfig.webUrl', () {
    test('production shares links against the public web client', () {
      expect(EnvironmentConfig.production.webUrl, 'https://coves.social');
    });

    test('local shares links against the local frontend host', () {
      expect(EnvironmentConfig.local.webUrl, 'http://127.0.0.1:8080');
      // The API base is unrelated to the web origin and stays as it is.
      expect(EnvironmentConfig.local.apiUrl, 'http://localhost:8080');
    });
  });

  group('EnvironmentConfig.test', () {
    test('points every requested endpoint at a closed loopback port', () {
      const config = EnvironmentConfig.test;
      expect(config.environment, Environment.test);
      expect(config.isProduction, isFalse);
      expect(config.isLocal, isFalse);
      expect(config.apiUrl, 'http://127.0.0.1:1');
      expect(
        config.handleResolverUrl,
        'http://127.0.0.1:1/xrpc/com.atproto.identity.resolveHandle',
      );
      expect(config.plcDirectoryUrl, 'http://127.0.0.1:1');
      // Share links only; never requested.
      expect(config.webUrl, 'https://coves.social');
    });

    test('is the current config under the flutter test runner', () {
      expect(EnvironmentConfig.current, isConfig(EnvironmentConfig.test));
    });
  });

  group('EnvironmentConfig.resolve', () {
    EnvironmentConfig resolve({
      String environmentOverride = '',
      String environmentShorthand = '',
      String flavor = '',
      bool isFlutterTest = true,
    }) => EnvironmentConfig.resolve(
      environmentOverride: environmentOverride,
      environmentShorthand: environmentShorthand,
      flavor: flavor,
      isFlutterTest: isFlutterTest,
    );

    test('defaults to production outside the test runner', () {
      expect(
        resolve(isFlutterTest: false),
        isConfig(EnvironmentConfig.production),
      );
    });

    test('defaults to test under the test runner', () {
      expect(resolve(), isConfig(EnvironmentConfig.test));
    });

    test('ENVIRONMENT override selects local or production', () {
      expect(
        resolve(environmentOverride: 'local'),
        isConfig(EnvironmentConfig.local),
      );
      expect(
        resolve(environmentOverride: 'production'),
        isConfig(EnvironmentConfig.production),
      );
    });

    test('ENV shorthand selects local or production', () {
      for (final value in ['dev', 'local']) {
        expect(
          resolve(environmentShorthand: value),
          isConfig(EnvironmentConfig.local),
          reason: 'ENV=$value',
        );
      }
      for (final value in ['prod', 'production']) {
        expect(
          resolve(environmentShorthand: value),
          isConfig(EnvironmentConfig.production),
          reason: 'ENV=$value',
        );
      }
    });

    test('flavor selects local or production', () {
      expect(resolve(flavor: 'dev'), isConfig(EnvironmentConfig.local));
      expect(resolve(flavor: 'prod'), isConfig(EnvironmentConfig.production));
    });

    test('ENVIRONMENT beats ENV, and ENV beats flavor', () {
      expect(
        resolve(
          environmentOverride: 'local',
          environmentShorthand: 'prod',
          flavor: 'prod',
        ),
        isConfig(EnvironmentConfig.local),
      );
      expect(
        resolve(environmentShorthand: 'local', flavor: 'prod'),
        isConfig(EnvironmentConfig.local),
      );
    });

    // The resolve helper above passes '' for every omitted define.
    test('empty values fall through to the next priority', () {
      expect(resolve(flavor: 'dev'), isConfig(EnvironmentConfig.local));
      expect(resolve(), isConfig(EnvironmentConfig.test));
      expect(
        resolve(isFlutterTest: false),
        isConfig(EnvironmentConfig.production),
      );
    });

    /// A [StateError] whose message names the define, the rejected value
    /// and every accepted value.
    Matcher throwsStateErrorNaming(
      String define,
      String value,
      List<String> accepted,
    ) => throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        allOf([
          contains(define),
          contains(value),
          for (final acceptedValue in accepted) contains(acceptedValue),
        ]),
      ),
    );

    test('unrecognized ENVIRONMENT throws instead of falling through', () {
      // ENV accepts dev but ENVIRONMENT does not; the typo must not
      // silently select production.
      expect(
        () => resolve(environmentOverride: 'dev', flavor: 'dev'),
        throwsStateErrorNaming('ENVIRONMENT', 'dev', ['local', 'production']),
      );
      expect(
        () => resolve(environmentOverride: 'dev', isFlutterTest: false),
        throwsStateErrorNaming('ENVIRONMENT', 'dev', ['local', 'production']),
      );
    });

    test('unrecognized ENV throws instead of falling through', () {
      expect(
        () => resolve(environmentShorthand: 'bogus'),
        throwsStateErrorNaming('ENV', 'bogus', [
          'dev',
          'local',
          'prod',
          'production',
        ]),
      );
      expect(
        () => resolve(environmentShorthand: 'bogus', isFlutterTest: false),
        throwsStateErrorNaming('ENV', 'bogus', [
          'dev',
          'local',
          'prod',
          'production',
        ]),
      );
    });

    test('unrecognized flavor throws instead of falling through', () {
      expect(
        () => resolve(flavor: 'staging'),
        throwsStateErrorNaming('FLUTTER_APP_FLAVOR', 'staging', [
          'dev',
          'prod',
        ]),
      );
      expect(
        () => resolve(flavor: 'staging', isFlutterTest: false),
        throwsStateErrorNaming('FLUTTER_APP_FLAVOR', 'staging', [
          'dev',
          'prod',
        ]),
      );
    });
  });
}
