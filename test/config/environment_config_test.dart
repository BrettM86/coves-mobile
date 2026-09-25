import 'package:coves_flutter/config/environment_config.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
