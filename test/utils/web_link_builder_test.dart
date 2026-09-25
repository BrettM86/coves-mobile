import 'package:coves_flutter/config/environment_config.dart';
import 'package:coves_flutter/utils/web_link_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const production = WebLinkBuilder(webUrl: 'https://coves.social');
  const communityDid = 'did:plc:community456';

  group('WebLinkBuilder.community', () {
    test('local community uses the bare name segment', () {
      expect(
        production.community(
          did: communityDid,
          name: 'Gaming',
          origin: 'coves.social',
        ),
        'https://coves.social/c/gaming',
      );
    });

    test('trims and lowercases the name and the origin', () {
      expect(
        production.community(
          did: communityDid,
          name: ' Gaming ',
          origin: ' COVES.SOCIAL ',
        ),
        'https://coves.social/c/gaming',
      );
    });

    test('remote community keeps a literal @ between name and origin', () {
      expect(
        production.community(
          did: communityDid,
          name: 'ComicStrips',
          origin: 'Lemmy.World',
        ),
        'https://coves.social/c/comicstrips@lemmy.world',
      );
    });

    test('local match ignores the port in the web URL', () {
      const local = WebLinkBuilder(webUrl: 'http://127.0.0.1:8080');
      expect(
        local.community(
          did: communityDid,
          name: 'Gaming',
          origin: '127.0.0.1',
        ),
        'http://127.0.0.1:8080/c/gaming',
      );
    });

    test('a trailing slash on the web URL does not double up', () {
      const trailingSlash = WebLinkBuilder(webUrl: 'https://coves.social/');
      expect(
        trailingSlash.community(
          did: communityDid,
          name: 'Gaming',
          origin: 'coves.social',
        ),
        'https://coves.social/c/gaming',
      );
    });

    test('a 63-character name is still a valid DNS label', () {
      const longestValidName =
          'gaming-community-with-a-very-long-but-still-valid-name-abcdefgh';
      expect(longestValidName.length, 63);
      expect(
        production.community(
          did: communityDid,
          name: longestValidName,
          origin: 'coves.social',
        ),
        'https://coves.social/c/gaming-community-with-a-very-long-but-'
        'still-valid-name-abcdefgh',
      );
    });
  });

  group('WebLinkBuilder.community fallbacks', () {
    // The web matcher accepts a bare DID for /c/ and redirects it to the
    // canonical form, so anything canonicalCommunityParam rejects falls
    // back to the DID segment.
    const didLink = 'https://coves.social/c/did%3Aplc%3Acommunity456';

    test('null origin falls back to the DID', () {
      expect(
        production.community(did: communityDid, name: 'Gaming'),
        didLink,
      );
    });

    test('blank origin falls back to the DID', () {
      expect(
        production.community(
          did: communityDid,
          name: 'Gaming',
          origin: '   ',
        ),
        didLink,
      );
    });

    test('blank name falls back to the DID', () {
      expect(
        production.community(
          did: communityDid,
          name: '   ',
          origin: 'coves.social',
        ),
        didLink,
      );
    });

    test('the DID segment is percent-encoded exactly once', () {
      final link = production.community(did: communityDid, name: 'Gaming');
      expect(link, didLink);
      expect(link, isNot(contains('%253A')));
    });

    test('a name with an underscore falls back to the DID', () {
      expect(
        production.community(
          did: communityDid,
          name: 'cool_stuff',
          origin: 'coves.social',
        ),
        didLink,
      );
    });

    test('a dotted name falls back to the DID', () {
      expect(
        production.community(
          did: communityDid,
          name: 'a.b',
          origin: 'coves.social',
        ),
        didLink,
      );
    });

    test('a 64-character name falls back to the DID', () {
      const overlongName =
          'gaming-community-with-a-very-long-but-still-valid-name-abcdefghi';
      expect(overlongName.length, 64);
      expect(
        production.community(
          did: communityDid,
          name: overlongName,
          origin: 'coves.social',
        ),
        didLink,
      );
    });

    test('a remote origin with a space falls back to the DID', () {
      expect(
        production.community(
          did: communityDid,
          name: 'Gaming',
          origin: 'not a domain',
        ),
        didLink,
      );
    });

    test('a remote origin with no dot falls back to the DID', () {
      expect(
        production.community(
          did: communityDid,
          name: 'Gaming',
          origin: 'nodots',
        ),
        didLink,
      );
    });

    test('a remote origin with an underscore falls back to the DID', () {
      expect(
        production.community(
          did: communityDid,
          name: 'Gaming',
          origin: 'exa_mple.com',
        ),
        didLink,
      );
    });
  });

  group('WebLinkBuilder.community with an unusable DID', () {
    // The DID segment is only a link because the web matcher accepts a bare
    // DID and redirects it. A value that is not a DID matches nothing there,
    // so there is no link to hand out at all.
    test('an unusable name and a relative-path DID has no link', () {
      expect(production.community(did: '..', name: ''), isNull);
    });

    test('an unusable name and a DID that is not a DID has no link', () {
      expect(production.community(did: 'x@y', name: 'Gaming'), isNull);
    });

    test('a canonical name form never looks at the DID', () {
      expect(
        production.community(
          did: 'x@y',
          name: 'Gaming',
          origin: 'coves.social',
        ),
        'https://coves.social/c/gaming',
      );
    });
  });

  group('WebLinkBuilder.post', () {
    // The owner segment names the repo the record lives in, which is the
    // at-URI authority: the author for a postv2 record, the community for a
    // legacy community-owned one.
    const authorDid = 'did:plc:author123';
    const authorHandle = 'alice.coves.social';
    const authorOwnedUri =
        'at://did:plc:author123/social.coves.community.postv2/3kabcxyz';
    const communityOwnedUri =
        'at://did:plc:community456/social.coves.community.post/3kabcxyz';

    test('an author-owned post uses the author handle as the owner', () {
      expect(
        production.post(
          postUri: authorOwnedUri,
          authorDid: authorDid,
          authorHandle: authorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz',
      );
    });

    test('a legacy community-owned post uses the community DID as the '
        'owner, not the author handle', () {
      expect(
        production.post(
          postUri: communityOwnedUri,
          authorDid: authorDid,
          authorHandle: authorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/did%3Aplc%3Acommunity456/3kabcxyz',
      );
    });

    test('a null author handle falls back to the authority DID', () {
      expect(
        production.post(
          postUri: authorOwnedUri,
          authorDid: authorDid,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/did%3Aplc%3Aauthor123/3kabcxyz',
      );
    });

    test('an unresolved handle.invalid falls back to the authority DID', () {
      expect(
        production.post(
          postUri: authorOwnedUri,
          authorDid: authorDid,
          authorHandle: 'handle.invalid',
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/did%3Aplc%3Aauthor123/3kabcxyz',
      );
    });

    test('a remote community keeps the name@origin segment', () {
      expect(
        production.post(
          postUri: authorOwnedUri,
          authorDid: authorDid,
          authorHandle: authorHandle,
          communityDid: communityDid,
          communityName: 'ComicStrips',
          communityOrigin: 'lemmy.world',
        ),
        'https://coves.social/c/comicstrips@lemmy.world/post/'
        'alice.coves.social/3kabcxyz',
      );
    });

    test('a community with no origin falls back to the community DID '
        'segment', () {
      expect(
        production.post(
          postUri: authorOwnedUri,
          authorDid: authorDid,
          authorHandle: authorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
        ),
        'https://coves.social/c/did%3Aplc%3Acommunity456/post/'
        'alice.coves.social/3kabcxyz',
      );
    });

    test('the owner DID is percent-encoded exactly once', () {
      final link = production.post(
        postUri: authorOwnedUri,
        authorDid: authorDid,
        communityDid: communityDid,
        communityName: 'Gaming',
        communityOrigin: 'coves.social',
      );
      expect(
        link,
        'https://coves.social/c/gaming/post/did%3Aplc%3Aauthor123/3kabcxyz',
      );
      expect(link, isNot(contains('%253A')));
    });
  });

  group('WebLinkBuilder.post with unusable identities', () {
    const authorDid = 'did:plc:author123';
    const authorOwnedUri =
        'at://did:plc:author123/social.coves.community.postv2/3kabcxyz';
    const authorDidLink =
        'https://coves.social/c/gaming/post/did%3Aplc%3Aauthor123/3kabcxyz';

    test('a relative-path author handle falls back to the authority DID', () {
      expect(
        production.post(
          postUri: authorOwnedUri,
          authorDid: authorDid,
          authorHandle: '..',
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        authorDidLink,
      );
    });

    test('a community DID that is not a DID still builds under the name', () {
      expect(
        production.post(
          postUri: authorOwnedUri,
          authorDid: authorDid,
          authorHandle: 'alice.coves.social',
          communityDid: 'x@y',
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz',
      );
    });

    test('a community DID that is not a DID and no origin has no link', () {
      expect(
        production.post(
          postUri: authorOwnedUri,
          authorDid: authorDid,
          authorHandle: 'alice.coves.social',
          communityDid: 'x@y',
          communityName: 'Gaming',
        ),
        isNull,
      );
    });
  });

  group('WebLinkBuilder.post with a did:web authority', () {
    const didWebUri =
        'at://did:web:alice.example.com/social.coves.community.postv2'
        '/3kabcxyz';

    test('a matching did:web handle is the owner segment', () {
      expect(
        production.post(
          postUri: didWebUri,
          authorDid: 'did:web:alice.example.com',
          authorHandle: 'alice.example.com',
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/alice.example.com/3kabcxyz',
      );
    });

    test('a did:web authority with no handle is encoded exactly once', () {
      expect(
        production.post(
          postUri: didWebUri,
          authorDid: 'did:web:alice.example.com',
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/'
        'did%3Aweb%3Aalice.example.com/3kabcxyz',
      );
    });

    test('a port-carrying did:web keeps its own escape intact', () {
      // did:web spells the port colon as %3A, and the path-segment encoding
      // escapes that percent in turn, so decoding the segment once hands the
      // DID back exactly as the record carries it.
      expect(
        production.post(
          postUri:
              'at://did:web:example.com%3A8080'
              '/social.coves.community.postv2/3kabcxyz',
          authorDid: 'did:web:example.com%3A8080',
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/'
        'did%3Aweb%3Aexample.com%253A8080/3kabcxyz',
      );
    });
  });

  group('WebLinkBuilder.post malformed URIs', () {
    // Stricter than the web's parser on purpose: only an exact
    // at://<authority>/<collection>/<rkey> yields a link, so a malformed
    // record URI is never turned into a URL that points somewhere wrong.
    String? postLinkFor(String postUri) => production.post(
          postUri: postUri,
          authorDid: 'did:plc:author123',
          authorHandle: 'alice.coves.social',
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        );

    test('an https URL is not an at-URI', () {
      expect(
        postLinkFor(
          'https://did:plc:author123/social.coves.community.postv2/3kabcxyz',
        ),
        isNull,
      );
    });

    test('the at:// scheme must start the URI', () {
      expect(
        postLinkFor(
          'xat://did:plc:author123/social.coves.community.postv2/3kabcxyz',
        ),
        isNull,
      );
    });

    test('an empty URI has no link', () {
      expect(postLinkFor(''), isNull);
    });

    test('a bare scheme has no link', () {
      expect(postLinkFor('at://'), isNull);
    });

    test('a missing record key has no link', () {
      expect(
        postLinkFor('at://did:plc:author123/social.coves.community.postv2'),
        isNull,
      );
    });

    test('a trailing slash is not a record key', () {
      expect(
        postLinkFor('at://did:plc:author123/social.coves.community.postv2/'),
        isNull,
      );
    });

    test('a missing collection has no link', () {
      expect(postLinkFor('at://did:plc:author123'), isNull);
    });

    test('an empty authority has no link', () {
      expect(
        postLinkFor('at:///social.coves.community.postv2/3kabcxyz'),
        isNull,
      );
    });

    test('an extra path segment has no link', () {
      expect(
        postLinkFor(
          'at://did:plc:author123/social.coves.community.postv2/3kabcxyz'
          '/extra',
        ),
        isNull,
      );
    });

    test('a query string has no link', () {
      expect(
        postLinkFor(
          'at://did:plc:author123/social.coves.community.postv2/3kabcxyz'
          '?x=1',
        ),
        isNull,
      );
    });

    test('a fragment has no link', () {
      expect(
        postLinkFor(
          'at://did:plc:author123/social.coves.community.postv2/3kabcxyz'
          '#frag',
        ),
        isNull,
      );
    });

    test('a handle authority has no link', () {
      // The AppView always emits DID authorities; echoing a handle as the
      // owner segment would address a repo the record may not live in.
      expect(
        postLinkFor(
          'at://alice.coves.social/social.coves.community.postv2/3kabcxyz',
        ),
        isNull,
      );
    });

    test('whitespace inside the record key has no link', () {
      expect(
        postLinkFor(
          'at://did:plc:author123/social.coves.community.postv2/3k abc',
        ),
        isNull,
      );
    });
  });

  group('WebLinkBuilder.comment', () {
    // The commenter segment follows the same repo rule as the post owner,
    // but against the comment URI's authority: the handle only when the
    // commenter ref proves the comment lives in that repo.
    const postUri =
        'at://did:plc:author123/social.coves.community.postv2/3kabcxyz';
    const postAuthorDid = 'did:plc:author123';
    const postAuthorHandle = 'alice.coves.social';
    const commentUri =
        'at://did:plc:commenter789/social.coves.community.comment/3kcmt001';
    const commenterDid = 'did:plc:commenter789';
    const didPermalink = 'https://coves.social/c/gaming/post/'
        'alice.coves.social/3kabcxyz/comment/'
        'did%3Aplc%3Acommenter789/3kcmt001';

    test('a resolved commenter handle is the commenter segment', () {
      expect(
        production.comment(
          commentUri: commentUri,
          commenterDid: commenterDid,
          commenterHandle: 'bob.coves.social',
          postUri: postUri,
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz'
        '/comment/bob.coves.social/3kcmt001',
      );
    });

    test('a null commenter handle falls back to the authority DID', () {
      expect(
        production.comment(
          commentUri: commentUri,
          commenterDid: commenterDid,
          postUri: postUri,
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        didPermalink,
      );
    });

    test('an unresolved handle.invalid falls back to the authority DID', () {
      expect(
        production.comment(
          commentUri: commentUri,
          commenterDid: commenterDid,
          commenterHandle: 'handle.invalid',
          postUri: postUri,
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        didPermalink,
      );
    });

    test('an absent commenter still yields the DID permalink', () {
      // A deleted or unhydrated comment author leaves the URI authority as
      // the only identity, which is a working permalink on its own.
      expect(
        production.comment(
          commentUri: commentUri,
          postUri: postUri,
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        didPermalink,
      );
    });

    test('a commenter from another repo does not lend its handle', () {
      expect(
        production.comment(
          commentUri: commentUri,
          commenterDid: postAuthorDid,
          commenterHandle: postAuthorHandle,
          postUri: postUri,
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        didPermalink,
      );
    });

    test('a legacy community-owned post in a remote community composes', () {
      expect(
        production.comment(
          commentUri: commentUri,
          commenterDid: commenterDid,
          commenterHandle: 'bob.coves.social',
          postUri:
              'at://did:plc:community456/social.coves.community.post/3kabcxyz',
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'ComicStrips',
          communityOrigin: 'lemmy.world',
        ),
        'https://coves.social/c/comicstrips@lemmy.world/post/'
        'did%3Aplc%3Acommunity456/3kabcxyz'
        '/comment/bob.coves.social/3kcmt001',
      );
    });

    test('the commenter DID is percent-encoded exactly once', () {
      final link = production.comment(
        commentUri: commentUri,
        commenterDid: commenterDid,
        postUri: postUri,
        postAuthorDid: postAuthorDid,
        postAuthorHandle: postAuthorHandle,
        communityDid: communityDid,
        communityName: 'Gaming',
        communityOrigin: 'coves.social',
      );
      expect(link, didPermalink);
      expect(link, isNot(contains('%253A')));
    });

    test('a comment URI with a query string has no link', () {
      expect(
        production.comment(
          commentUri: '$commentUri?x=1',
          commenterDid: commenterDid,
          commenterHandle: 'bob.coves.social',
          postUri: postUri,
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        isNull,
      );
    });

    test('a comment URI with a handle authority has no link', () {
      expect(
        production.comment(
          commentUri:
              'at://bob.coves.social/social.coves.community.comment/3kcmt001',
          commenterDid: commenterDid,
          commenterHandle: 'bob.coves.social',
          postUri: postUri,
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        isNull,
      );
    });

    test('a malformed post URI has no link even with a valid comment URI', () {
      expect(
        production.comment(
          commentUri: commentUri,
          commenterDid: commenterDid,
          commenterHandle: 'bob.coves.social',
          postUri:
              'https://did:plc:author123/social.coves.community.postv2/3kabcxyz',
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: communityDid,
          communityName: 'Gaming',
          communityOrigin: 'coves.social',
        ),
        isNull,
      );
    });
  });

  group('WebLinkBuilder.comment with unusable identities', () {
    const postUri =
        'at://did:plc:author123/social.coves.community.postv2/3kabcxyz';
    const postAuthorDid = 'did:plc:author123';
    const postAuthorHandle = 'alice.coves.social';
    const commentUri =
        'at://did:plc:commenter789/social.coves.community.comment/3kcmt001';
    const commenterDid = 'did:plc:commenter789';

    test(
      'a relative-path commenter handle falls back to the authority DID',
      () {
        expect(
          production.comment(
            commentUri: commentUri,
            commenterDid: commenterDid,
            commenterHandle: '..',
            postUri: postUri,
            postAuthorDid: postAuthorDid,
            postAuthorHandle: postAuthorHandle,
            communityDid: communityDid,
            communityName: 'Gaming',
            communityOrigin: 'coves.social',
          ),
          'https://coves.social/c/gaming/post/alice.coves.social/3kabcxyz'
          '/comment/did%3Aplc%3Acommenter789/3kcmt001',
        );
      },
    );

    test('a community DID that is not a DID and no origin has no link', () {
      expect(
        production.comment(
          commentUri: commentUri,
          commenterDid: commenterDid,
          commenterHandle: 'bob.coves.social',
          postUri: postUri,
          postAuthorDid: postAuthorDid,
          postAuthorHandle: postAuthorHandle,
          communityDid: 'x@y',
          communityName: 'Gaming',
        ),
        isNull,
      );
    });
  });

  group('WebLinkBuilder.profile', () {
    // The web's actor matcher accepts a DID or a DNS handle, so an
    // unresolved handle is addressed by DID instead.
    const authorDid = 'did:plc:author123';
    const didLink = 'https://coves.social/profile/did%3Aplc%3Aauthor123';

    test('a resolved handle is the profile segment', () {
      expect(
        production.profile(did: authorDid, handle: 'alice.coves.social'),
        'https://coves.social/profile/alice.coves.social',
      );
    });

    test('a null handle falls back to the DID', () {
      expect(production.profile(did: authorDid), didLink);
    });

    test('an empty handle falls back to the DID', () {
      expect(production.profile(did: authorDid, handle: ''), didLink);
    });

    test('a blank handle falls back to the DID', () {
      expect(production.profile(did: authorDid, handle: '   '), didLink);
    });

    test('an unresolved handle.invalid falls back to the DID', () {
      expect(
        production.profile(did: authorDid, handle: 'handle.invalid'),
        didLink,
      );
    });

    test('surrounding whitespace is trimmed off the handle', () {
      expect(
        production.profile(did: authorDid, handle: ' alice.coves.social '),
        'https://coves.social/profile/alice.coves.social',
      );
    });

    test('the DID segment is percent-encoded exactly once', () {
      final link = production.profile(did: authorDid);
      expect(link, didLink);
      expect(link, isNot(contains('%253A')));
    });
  });

  group('WebLinkBuilder.profile handle grammar', () {
    // A handle segment has to satisfy the same hostname grammar as a remote
    // community origin: the web's handle matcher is the one rule, and a
    // segment outside it either 404s or addresses another route entirely.
    const authorDid = 'did:plc:author123';
    const didLink = 'https://coves.social/profile/did%3Aplc%3Aauthor123';

    test('a parent-directory handle falls back to the DID', () {
      expect(production.profile(did: authorDid, handle: '..'), didLink);
    });

    test('a current-directory handle falls back to the DID', () {
      expect(production.profile(did: authorDid, handle: '.'), didLink);
    });

    test('a handle with a space falls back to the DID', () {
      expect(
        production.profile(did: authorDid, handle: 'not a handle'),
        didLink,
      );
    });

    test('an undotted handle falls back to the DID', () {
      expect(production.profile(did: authorDid, handle: 'nodots'), didLink);
    });

    test('a handle with an underscore falls back to the DID', () {
      expect(
        production.profile(did: authorDid, handle: 'exa_mple.com'),
        didLink,
      );
    });
  });

  group('WebLinkBuilder.profile with no usable segment', () {
    // With no usable handle the DID is the segment, so a DID the web's actor
    // matcher would reject leaves nothing to link to.
    test('a parent-directory DID and no handle has no link', () {
      expect(production.profile(did: '..'), isNull);
    });

    test('a DID that is not a DID has no link', () {
      expect(production.profile(did: 'not-a-did'), isNull);
    });
  });

  group('WebLinkBuilder.current', () {
    test('builds against the current environment web origin', () {
      expect(
        WebLinkBuilder.current().webUrl,
        EnvironmentConfig.current.webUrl,
      );
      // Under `flutter test` the current environment is production.
      expect(WebLinkBuilder.current().webUrl, 'https://coves.social');
    });

    test('links built from it carry the production origin', () {
      expect(
        WebLinkBuilder.current().profile(
          did: 'did:plc:author123',
          handle: 'alice.coves.social',
        ),
        'https://coves.social/profile/alice.coves.social',
      );
    });
  });
}
