import 'package:coves_flutter/models/bluesky_profile_import.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _getPath = '/xrpc/social.coves.actor.getBlueskyProfileImport';
const _importPath = '/xrpc/social.coves.actor.importBlueskyProfile';
const _dismissPath = '/xrpc/social.coves.actor.dismissBlueskyProfileImport';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CovesApiService Bluesky profile import', () {
    late Dio dio;
    late DioAdapter adapter;
    late CovesApiService service;
    late List<RequestOptions> requests;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
      requests = [];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.next(options);
          },
        ),
      );
      adapter = DioAdapter(dio: dio);
      service = CovesApiService(
        sessionKeyOf: () => (did: 'did:plc:alice', sessionId: 'session-1'),
        dio: dio,
        tokenGetter: () async => 'test-token',
      );
    });

    tearDown(() => service.dispose());

    test('getBlueskyProfileImport GETs its endpoint and parses the '
        'offer', () async {
      adapter.onGet(
        _getPath,
        (server) => server.reply(200, {
          'status': 'offer',
          'fields': [
            {'field': 'displayName', 'bluesky': 'Alice', 'covesIsEmpty': true},
            {
              'field': 'avatar',
              'blueskyImageUrl': 'https://cdn.bsky.app/img/avatar/a@jpeg',
              'covesIsEmpty': false,
            },
          ],
        }),
      );

      final result = await service.getBlueskyProfileImport();

      expect(requests.single.method, 'GET');
      expect(requests.single.path, _getPath);
      expect(result.status, BlueskyProfileImportStatus.offer);
      expect(
        [
          for (final view in result.fields)
            (view.field, view.bluesky, view.blueskyImageUrl, view.covesIsEmpty),
        ],
        [
          (BlueskyProfileField.displayName, 'Alice', null, true),
          (
            BlueskyProfileField.avatar,
            null,
            'https://cdn.bsky.app/img/avatar/a@jpeg',
            false,
          ),
        ],
      );
    });

    test('getBlueskyProfileImport with an unknown status throws an '
        'ApiException', () async {
      adapter.onGet(
        _getPath,
        (server) =>
            server.reply(200, {'status': 'later', 'fields': <Object>[]}),
      );

      await expectLater(
        service.getBlueskyProfileImport(),
        throwsA(isA<ApiException>()),
      );
    });

    test('importBlueskyProfile POSTs the field wire names and returns the '
        'imported fields', () async {
      adapter.onPost(
        _importPath,
        (server) => server.reply(200, {
          'uri': 'at://did:plc:alice/social.coves.actor.profile/self',
          'cid': 'bafyreiprofile',
          'imported': ['displayName', 'avatar', 'pronouns'],
        }),
        data: Matchers.any,
      );

      final imported = await service.importBlueskyProfile([
        BlueskyProfileField.displayName,
        BlueskyProfileField.avatar,
      ]);

      expect(requests.single.method, 'POST');
      expect(requests.single.path, _importPath);
      expect(requests.single.data, {
        'fields': ['displayName', 'avatar'],
      });
      expect(imported, [
        BlueskyProfileField.displayName,
        BlueskyProfileField.avatar,
      ]);
    });

    test('importBlueskyProfile surfaces NothingToImport and Conflict as '
        'ApiException error codes', () async {
      final rows = <(int, String)>[(400, 'NothingToImport'), (409, 'Conflict')];

      for (final (statusCode, errorCode) in rows) {
        adapter.onPost(
          _importPath,
          (server) => server.reply(statusCode, {'error': errorCode}),
          data: Matchers.any,
        );

        await expectLater(
          service.importBlueskyProfile([BlueskyProfileField.displayName]),
          throwsA(
            isA<ApiException>().having(
              (error) => error.errorCode,
              'errorCode',
              errorCode,
            ),
          ),
          reason: errorCode,
        );
      }
    });

    test('dismissBlueskyProfileImport POSTs with no body and accepts an '
        'empty 200', () async {
      adapter.onPost(
        _dismissPath,
        (server) => server.reply(200, null),
        data: Matchers.any,
      );

      // An error is captured as the outcome so a failure reports what came
      // back next to the expected completion
      final outcome = await service.dismissBlueskyProfileImport().then<Object?>(
        (_) => 'completed',
        onError: (Object error) => error,
      );

      expect(outcome, 'completed');
      expect(requests.single.method, 'POST');
      expect(requests.single.path, _dismissPath);
      expect(requests.single.data, isNull);
    });
  });
}
