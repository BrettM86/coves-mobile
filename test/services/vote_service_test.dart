import 'package:coves_flutter/models/coves_session.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/vote_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoteService', () {
    group('VoteResponse', () {
      test('should create response with uri, cid, and rkey', () {
        const response = VoteResponse(
          uri: 'at://did:plc:test/social.coves.feed.vote/123',
          cid: 'bafy123',
          rkey: '123',
          deleted: false,
        );

        expect(response.uri, 'at://did:plc:test/social.coves.feed.vote/123');
        expect(response.cid, 'bafy123');
        expect(response.rkey, '123');
        expect(response.deleted, false);
      });

      test('should create deleted response', () {
        const response = VoteResponse(deleted: true);

        expect(response.deleted, true);
        expect(response.uri, null);
        expect(response.cid, null);
        expect(response.rkey, null);
      });
    });

    // DioException → ApiException mapping is covered by
    // api_exceptions_test.dart — this test just seals the delegation.
    group('createVote error mapping', () {
      test('surfaces a 500 as ServerException via the canonical mapper',
          () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://api.test.coves.social'));
        final dioAdapter = DioAdapter(dio: dio);
        final service = VoteService(
          sessionGetter: () async => const CovesSession(
            token: 'test-token',
            did: 'did:plc:test',
            sessionId: 'session-1',
          ),
          didGetter: () => 'did:plc:test',
          dio: dio,
        );

        dioAdapter.onPost(
          '/xrpc/social.coves.feed.vote.create',
          (server) => server.reply(500, {'message': 'boom'}),
          data: {
            'subject': {'uri': 'at://did:plc:test/post/1', 'cid': 'cid1'},
            'direction': 'up',
          },
        );

        await expectLater(
          service.createVote(
            postUri: 'at://did:plc:test/post/1',
            postCid: 'cid1',
          ),
          throwsA(
            isA<ServerException>().having((e) => e.message, 'message', 'boom'),
          ),
        );
      });
    });
  });
}
