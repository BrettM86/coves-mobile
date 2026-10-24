import 'dart:typed_data';

import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late CovesApiService service;
  late List<RequestOptions> requests;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
    requests = [];
    // Resolves every request locally; an over-limit image must never reach
    // this point
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'uri': 'at://did:plc:subject/social.coves.record/self',
                'cid': 'record-cid',
                'did': 'did:plc:community',
                'handle': 'c-test.coves.social',
              },
            ),
          );
        },
      ),
    );
    service = CovesApiService(
      dio: dio,
      tokenGetter: () async => null,
      sessionKeyOf: () => null,
    );
  });

  tearDown(() => service.dispose());

  test('images over the backend blob limits are rejected before any request '
      '(avatar 1,000,000 bytes, banner 2,000,000 bytes)', () async {
    final rows = <(String, Future<Object> Function())>[
      (
        'profile avatar 1,000,500 bytes',
        () => service.updateProfile(
          avatarBytes: Uint8List(1000500),
          avatarMimeType: 'image/jpeg',
        ),
      ),
      (
        'profile banner 2,000,500 bytes',
        () => service.updateProfile(
          bannerBytes: Uint8List(2000500),
          bannerMimeType: 'image/jpeg',
        ),
      ),
      (
        'community avatar 1,000,500 bytes',
        () => service.updateCommunity(
          communityDid: 'did:plc:community',
          imageBytes: Uint8List(1000500),
          mimeType: 'image/jpeg',
        ),
      ),
    ];

    for (final (name, call) in rows) {
      requests.clear();
      final outcome = await call().then<Object>(
        (response) => response,
        onError: (Object error) => error,
      );
      expect(outcome, isA<ApiException>(), reason: name);
      expect(requests, isEmpty, reason: name);
    }
  });
}
