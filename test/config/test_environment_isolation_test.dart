// Real-network acceptance test: a real CovesApiService under the flutter
// test runner must never reach production.
//
// This file deliberately uses plain `test()` and never initializes
// TestWidgetsFlutterBinding: the binding installs an HttpOverrides client
// that answers every request with a synthetic 400, which would hide where
// requests actually go.
import 'package:coves_flutter/config/environment_config.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/coves_http.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a real CovesApiService under flutter test fails fast against a '
      'closed loopback port instead of reaching production', () async {
    // Safety gate: this must pass before any request is sent, so a
    // regression fails here without contacting production.
    final apiUrl = EnvironmentConfig.current.apiUrl;
    final apiUri = Uri.parse(apiUrl);
    expect(apiUri.host, '127.0.0.1', reason: 'apiUrl was $apiUrl');
    expect(apiUri.port, 1, reason: 'apiUrl was $apiUrl');

    // Also gate on the base URL the HTTP client actually uses, so a
    // createCovesDio that stops reading EnvironmentConfig fails here too.
    final gateDio = createCovesDio();
    final dioBaseUrl = gateDio.options.baseUrl;
    gateDio.close();
    final dioBaseUri = Uri.parse(dioBaseUrl);
    expect(dioBaseUri.host, '127.0.0.1', reason: 'baseUrl was $dioBaseUrl');
    expect(dioBaseUri.port, 1, reason: 'baseUrl was $dioBaseUrl');

    final apiService = CovesApiService(tokenGetter: () async => null);
    addTearDown(apiService.dispose);

    Object? thrown;
    try {
      await apiService.getDiscover();
    } on Object catch (error) {
      thrown = error;
    }

    expect(thrown, isA<NetworkException>());
    final originalError = (thrown! as NetworkException).originalError;
    expect(originalError, isA<DioException>());
    final dioException = originalError as DioException;
    expect(dioException.type, DioExceptionType.connectionError);
    expect(dioException.requestOptions.uri.host, '127.0.0.1');
    expect(dioException.requestOptions.uri.port, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
