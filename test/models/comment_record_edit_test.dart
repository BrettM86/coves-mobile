// B1: CommentRecord keeps the stored record's raw embed, langs and labels,
// so an edit can resend them verbatim (the update procedure replaces the
// whole record). The record embed is the raw form with blob refs, distinct
// from the AppView's #view embed on the same CommentView.

import 'package:coves_flutter/models/comment.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> commentViewJson({required Map<String, dynamic> record}) {
  return {
    'uri': 'at://did:plc:author/social.coves.community.comment/e1',
    'cid': 'cid-e1',
    'record': record,
    'createdAt': '2026-01-01T00:00:00Z',
    'indexedAt': '2026-01-01T00:00:00Z',
    'author': {'did': 'did:plc:author', 'handle': 'author.coves.test'},
    'post': {
      'uri': 'at://did:plc:postauthor/social.coves.community.post/p',
      'cid': 'cid-p',
    },
    'stats': {'upvotes': 1, 'downvotes': 0, 'score': 1, 'replyCount': 0},
    'embed': {
      r'$type': 'social.coves.embed.images#view',
      'images': [
        {
          'thumb': 'https://cdn.coves.test/thumb/bafkreiimage',
          'fullsize': 'https://cdn.coves.test/full/bafkreiimage',
          'alt': 'a cat',
        },
      ],
    },
  };
}

void main() {
  test('fromJson keeps the record embed, langs and labels verbatim', () {
    final view = CommentView.fromJson(
      commentViewJson(
        record: {
          r'$type': 'social.coves.community.comment',
          'content': 'Edited body',
          'embed': {
            r'$type': 'social.coves.embed.images',
            'images': [
              {
                'image': {
                  r'$type': 'blob',
                  'ref': {r'$link': 'bafkreiimage'},
                  'mimeType': 'image/jpeg',
                  'size': 12345,
                },
                'alt': 'a cat',
              },
            ],
          },
          'langs': ['en', 'fr'],
          'labels': {
            r'$type': 'com.atproto.label.defs#selfLabels',
            'values': [
              {'val': 'nudity'},
            ],
          },
        },
      ),
    );

    final record = view.record!;
    expect(record.embed, {
      r'$type': 'social.coves.embed.images',
      'images': [
        {
          'image': {
            r'$type': 'blob',
            'ref': {r'$link': 'bafkreiimage'},
            'mimeType': 'image/jpeg',
            'size': 12345,
          },
          'alt': 'a cat',
        },
      ],
    });
    expect(record.langs, ['en', 'fr']);
    expect(record.labels, {
      r'$type': 'com.atproto.label.defs#selfLabels',
      'values': [
        {'val': 'nudity'},
      ],
    });
    // The view embed stays the AppView's #view form.
    expect(view.embed![r'$type'], 'social.coves.embed.images#view');
  });

  test('fromJson leaves embed, langs and labels null when absent', () {
    final view = CommentView.fromJson(
      commentViewJson(
        record: {
          r'$type': 'social.coves.community.comment',
          'content': 'Plain body',
        },
      ),
    );

    final record = view.record!;
    expect(record.embed, isNull);
    expect(record.langs, isNull);
    expect(record.labels, isNull);
  });
}
