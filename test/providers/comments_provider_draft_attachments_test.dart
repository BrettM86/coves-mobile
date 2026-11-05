import 'dart:io';

import 'package:coves_flutter/models/image_attachment.dart';
import 'package:coves_flutter/models/post.dart';
import 'package:coves_flutter/providers/comments_provider.dart';
import 'package:coves_flutter/services/comments_provider_cache.dart';
import 'package:coves_flutter/widgets/composer/composer_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/image_fixtures.dart';
import '../test_helpers/test_mocks.dart';

const _parentUri = 'at://did:plc:author/social.coves.community.comment/parent';
const _otherParentUri =
    'at://did:plc:author/social.coves.community.comment/other';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late MockAuthProvider auth;
  late CommentsProvider provider;

  CommentsProvider createProvider() => CommentsProvider(
    auth,
    postUri: 'at://did:plc:test/social.coves.post.record/123',
    postCid: 'test-post-cid',
    apiService: MockCovesApiService(),
    voteProvider: MockVoteProvider(),
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('reply_draft_attachments');
    auth = MockAuthProvider();
    when(auth.isAuthenticated).thenReturn(true);
    provider = createProvider();
  });

  tearDown(() {
    provider.dispose();
    directory.deleteSync(recursive: true);
  });

  /// An uploaded attachment backed by a real file called [name].
  ImageAttachment attachment(String name, {bool ownsFile = true}) {
    final bytes = tinyPng4x3;
    return ImageAttachment(
      id: 'image-$name',
      file: File('${directory.path}/$name.png')..writeAsBytesSync(bytes),
      bytes: bytes,
      mimeType: 'image/png',
      ownsFile: ownsFile,
      blob: {
        'ref': {r'$link': 'bafkrei-$name'},
      },
      aspectRatio: EmbedAspectRatio(width: 4, height: 3),
      status: ImageAttachmentStatus.uploaded,
      progress: 1,
      alt: 'alt for $name',
    );
  }

  bool exists(String name) => File('${directory.path}/$name.png').existsSync();

  /// Polls the file system until [name]'s file is gone; fails after a
  /// bounded number of real-IO polls.
  Future<void> expectDeleted(String name) async {
    for (var i = 0; i < 100 && exists(name); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(exists(name), isFalse, reason: '$name.png should be deleted');
  }

  group('B3 reply draft attachments', () {
    test('B3 re-saving a draft as text only deletes the owned file of the '
        'attachment it no longer holds', () async {
      provider
        ..saveDraft(
          ComposerDraft(text: 'first'),
          parentUri: _parentUri,
          attachments: [attachment('a')],
        )
        ..saveDraft(ComposerDraft(text: 'second'), parentUri: _parentUri);

      await expectDeleted('a');
      expect(provider.getDraft(parentUri: _parentUri)?.text, 'second');
    });

    test('B3 clearing a draft deletes its owned files and keeps the file of an '
        'attachment that does not own it', () async {
      provider
        ..saveDraft(
          ComposerDraft(text: 'first'),
          parentUri: _parentUri,
          attachments: [attachment('a'), attachment('b', ownsFile: false)],
        )
        ..clearDraft(parentUri: _parentUri);

      await expectDeleted('a');
      expect(exists('b'), isTrue);
    });

    test('B3 replacing [A, B] with [B, C] deletes only A and keeps B and C in '
        'the draft', () async {
      final b = attachment('b');
      final c = attachment('c');
      provider
        ..saveDraft(
          ComposerDraft(text: 'first'),
          parentUri: _parentUri,
          attachments: [attachment('a'), b],
        )
        ..saveDraft(
          ComposerDraft(text: 'second'),
          parentUri: _parentUri,
          attachments: [b, c],
        );

      await expectDeleted('a');
      expect(exists('b'), isTrue);
      expect(exists('c'), isTrue);
      expect(provider.getDraft(parentUri: _parentUri)?.text, 'second');
      final taken = provider.takeDraftAttachments(parentUri: _parentUri);
      expect(taken, hasLength(2));
      expect(taken[0], same(b));
      expect(taken[1], same(c));
    });

    test('B3 takeDraftAttachments hands the attachment over intact and a later '
        'clearDraft leaves its file alone', () async {
      provider
        ..saveDraft(
          ComposerDraft(text: 'text'),
          parentUri: _parentUri,
          attachments: [attachment('a')],
        )
        ..saveDraft(
          ComposerDraft(text: 'other'),
          parentUri: _otherParentUri,
          attachments: [attachment('d')],
        );

      final taken = provider.takeDraftAttachments(parentUri: _parentUri);

      expect(taken, hasLength(1));
      expect(taken.single.alt, 'alt for a');
      expect(taken.single.blob, {
        'ref': {r'$link': 'bafkrei-a'},
      });
      expect(provider.getDraft(parentUri: _parentUri)?.text, 'text');

      provider
        ..clearDraft(parentUri: _parentUri)
        ..clearDraft(parentUri: _otherParentUri);
      // d's deletion is started after any of a's would be.
      await expectDeleted('d');
      expect(exists('a'), isTrue);
    });

    test('B3 disposing the provider deletes the owned files of every draft it '
        'holds', () async {
      createProvider()
        ..saveDraft(
          ComposerDraft(text: 'one'),
          parentUri: _parentUri,
          attachments: [attachment('a')],
        )
        ..saveDraft(
          ComposerDraft(text: ''),
          parentUri: _otherParentUri,
          attachments: [attachment('b')],
        )
        ..dispose();

      await expectDeleted('a');
      await expectDeleted('b');
    });

    test('B3 a draft saved into a disposed provider deletes its owned files '
        'and is not kept', () async {
      final disposed = createProvider()
        ..dispose()
        ..saveDraft(
          ComposerDraft(text: 'late'),
          parentUri: _parentUri,
          attachments: [attachment('a'), attachment('b', ownsFile: false)],
        );

      await expectDeleted('a');
      expect(exists('b'), isTrue);
      expect(disposed.hasDraft(parentUri: _parentUri), isFalse);
    });

    test('B3 a draft saved into a pinned provider after the cache cleared it '
        'on an account change deletes its owned files', () async {
      final fakeAuth = FakeAuthProvider(signedInDid: 'did:plc:alice');
      final votes = FakeVoteProvider(fakeAuth);
      final cache = CommentsProviderCache(
        authProvider: fakeAuth,
        voteProvider: votes,
        commentService: MockCommentService(),
        apiService: MockCovesApiService(),
      );
      addTearDown(votes.dispose);
      addTearDown(cache.dispose);
      final pinned = cache.acquireProvider(
        postUri: 'at://did:plc:test/social.coves.post.record/123',
        postCid: 'test-post-cid',
      );

      // Sign-out with the composer open: the cache disposes the pinned
      // provider before the composer hands its draft off.
      fakeAuth.setSignedInDid(null);
      pinned.saveDraft(
        ComposerDraft(text: 'late'),
        parentUri: _parentUri,
        attachments: [attachment('a')],
      );

      await expectDeleted('a');
      expect(pinned.takeDraftAttachments(parentUri: _parentUri), isEmpty);
    });

    test('B3 an image-only draft counts as a draft until it is cleared', () {
      provider.saveDraft(
        ComposerDraft(text: '  '),
        parentUri: _parentUri,
        attachments: [attachment('a')],
      );

      expect(provider.hasDraft(parentUri: _parentUri), isTrue);

      provider.clearDraft(parentUri: _parentUri);

      expect(provider.hasDraft(parentUri: _parentUri), isFalse);
    });
  });
}
