import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('B0 removePost delivers the literal uri to every listener', () {
    final broadcast = PostChangeBroadcast();
    final first = <PostChange>[];
    final second = <PostChange>[];
    broadcast
      ..addPostChangeListener(first.add)
      ..addPostChangeListener(second.add)
      ..removePost('at://did:plc:me/social.coves.community.post/p');

    expect(first, hasLength(1));
    expect(first.single, isA<PostRemoved>());
    expect(
      (first.single as PostRemoved).uri,
      'at://did:plc:me/social.coves.community.post/p',
    );
    expect(second, hasLength(1));
    expect(
      (second.single as PostRemoved).uri,
      'at://did:plc:me/social.coves.community.post/p',
    );
  });

  test('B0 replacePost delivers the identical post to every listener', () {
    final post = PostView(
      uri: 'at://did:plc:me/social.coves.community.post/p',
      cid: 'cid-p',
      rkey: 'p',
      author: AuthorView(did: 'did:plc:me', handle: 'me.test'),
      community: CommunityRef(did: 'did:plc:community', name: 'test'),
      createdAt: DateTime.utc(2025),
      indexedAt: DateTime.utc(2025),
      record: const PostRecord(title: 'Updated', content: 'Body'),
      stats: PostStats(upvotes: 2, downvotes: 0, score: 2, commentCount: 0),
    );
    final broadcast = PostChangeBroadcast();
    final first = <PostChange>[];
    final second = <PostChange>[];
    broadcast
      ..addPostChangeListener(first.add)
      ..addPostChangeListener(second.add)
      ..replacePost(post);

    expect(first, hasLength(1));
    expect(first.single, isA<PostReplaced>());
    expect(identical((first.single as PostReplaced).post, post), isTrue);
    expect(second, hasLength(1));
    expect(identical((second.single as PostReplaced).post, post), isTrue);
  });

  test('B0 removed listener receives no further post changes', () {
    final broadcast = PostChangeBroadcast();
    final received = <PostChange>[];
    broadcast
      ..addPostChangeListener(received.add)
      ..removePost('at://did:plc:me/social.coves.community.post/first');
    expect(received, hasLength(1));

    broadcast
      ..removePostChangeListener(received.add)
      ..removePost('at://did:plc:me/social.coves.community.post/second');
    expect(received, hasLength(1));
  });

  test('B0 a throwing listener does not stop later listeners, the publish '
      'does not throw, and the error is reported', () {
    final reportedErrors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = originalOnError);

    final listenerError = StateError('listener failed');
    final broadcast = PostChangeBroadcast();
    final later = <PostChange>[];
    broadcast
      ..addPostChangeListener((_) => throw listenerError)
      ..addPostChangeListener(later.add);

    expect(
      () =>
          broadcast.removePost('at://did:plc:me/social.coves.community.post/p'),
      returnsNormally,
    );

    expect(later, hasLength(1));
    expect(
      (later.single as PostRemoved).uri,
      'at://did:plc:me/social.coves.community.post/p',
    );
    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, same(listenerError));
  });

  test('B0 self-unsubscribe during dispatch still delivers to peers', () {
    final broadcast = PostChangeBroadcast();
    final received = <String>[];
    late PostChangeListener unsubscribe;
    unsubscribe = (change) {
      received.add('first');
      broadcast.removePostChangeListener(unsubscribe);
    };
    broadcast
      ..addPostChangeListener(unsubscribe)
      ..addPostChangeListener((change) => received.add('second'))
      ..removePost('at://did:plc:me/social.coves.community.post/p');

    expect(received, ['first', 'second']);
    broadcast.removePost('at://did:plc:me/social.coves.community.post/q');
    expect(received, ['first', 'second', 'second']);
  });
}
