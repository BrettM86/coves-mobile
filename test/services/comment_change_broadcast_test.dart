import 'package:coves_flutter/models/comment.dart';
import 'package:coves_flutter/services/comment_change_broadcast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/comment_removal_fixtures.dart';

CommentView _comment(String rkey) => fixtureComment(
  uri: 'at://did:plc:me/social.coves.community.comment/$rkey',
  authorDid: 'did:plc:me',
  text: 'Edited $rkey',
);

void main() {
  test('replaceComment delivers the identical comment to every listener', () {
    final comment = _comment('c');
    final broadcast = CommentChangeBroadcast();
    final first = <CommentView>[];
    final second = <CommentView>[];
    broadcast
      ..addCommentChangeListener(first.add)
      ..addCommentChangeListener(second.add)
      ..replaceComment(comment);

    expect(first, [same(comment)]);
    expect(second, [same(comment)]);
  });

  test('a removed listener receives no further comment changes', () {
    final broadcast = CommentChangeBroadcast();
    final received = <String>[];
    void listener(CommentView comment) => received.add(comment.uri);
    broadcast
      ..addCommentChangeListener(listener)
      ..replaceComment(_comment('first'));
    expect(received, ['at://did:plc:me/social.coves.community.comment/first']);

    broadcast
      ..removeCommentChangeListener(listener)
      ..replaceComment(_comment('second'));
    expect(received, ['at://did:plc:me/social.coves.community.comment/first']);
  });

  test('a throwing listener does not stop later listeners, the dispatch '
      'does not throw, and the error is reported', () {
    final reportedErrors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = originalOnError);

    final listenerError = StateError('listener failed');
    final comment = _comment('c');
    final broadcast = CommentChangeBroadcast();
    final later = <CommentView>[];
    broadcast
      ..addCommentChangeListener((_) => throw listenerError)
      ..addCommentChangeListener(later.add);

    expect(() => broadcast.replaceComment(comment), returnsNormally);

    expect(later, [same(comment)]);
    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, same(listenerError));
  });

  test('self-unsubscribe during dispatch still delivers to peers', () {
    final broadcast = CommentChangeBroadcast();
    final received = <String>[];
    late CommentChangeListener unsubscribe;
    unsubscribe = (comment) {
      received.add('first');
      broadcast.removeCommentChangeListener(unsubscribe);
    };
    broadcast
      ..addCommentChangeListener(unsubscribe)
      ..addCommentChangeListener((comment) => received.add('second'))
      ..replaceComment(_comment('c'));

    expect(received, ['first', 'second']);
    broadcast.replaceComment(_comment('d'));
    expect(received, ['first', 'second', 'second']);
  });
}
