import 'package:coves_flutter/services/vote_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    // api_exceptions_test.dart — VoteService delegates to the shared mapper.
  });
}
