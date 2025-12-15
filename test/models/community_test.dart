import 'package:coves_flutter/models/community.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommunitiesResponse', () {
    test('should parse valid JSON with communities', () {
      final json = {
        'communities': [
          {
            'did': 'did:plc:community1',
            'name': 'test-community',
            'handle': 'test.coves.social',
            'displayName': 'Test Community',
            'description': 'A test community',
            'avatar': 'https://example.com/avatar.jpg',
            'visibility': 'public',
            'subscriberCount': 100,
            'memberCount': 50,
            'postCount': 200,
          },
        ],
        'cursor': 'next-cursor',
      };

      final response = CommunitiesResponse.fromJson(json);

      expect(response.communities.length, 1);
      expect(response.cursor, 'next-cursor');
      expect(response.communities[0].did, 'did:plc:community1');
      expect(response.communities[0].name, 'test-community');
      expect(response.communities[0].displayName, 'Test Community');
    });

    test('should handle null communities array', () {
      final json = {
        'communities': null,
        'cursor': null,
      };

      final response = CommunitiesResponse.fromJson(json);

      expect(response.communities, isEmpty);
      expect(response.cursor, null);
    });

    test('should handle empty communities array', () {
      final json = {
        'communities': [],
        'cursor': null,
      };

      final response = CommunitiesResponse.fromJson(json);

      expect(response.communities, isEmpty);
      expect(response.cursor, null);
    });

    test('should parse without cursor', () {
      final json = {
        'communities': [
          {
            'did': 'did:plc:community1',
            'name': 'test-community',
          },
        ],
      };

      final response = CommunitiesResponse.fromJson(json);

      expect(response.cursor, null);
      expect(response.communities.length, 1);
    });
  });

  group('CommunityView', () {
    test('should parse complete JSON with all fields', () {
      final json = {
        'did': 'did:plc:community1',
        'name': 'test-community',
        'handle': 'test.coves.social',
        'displayName': 'Test Community',
        'description': 'A community for testing',
        'avatar': 'https://example.com/avatar.jpg',
        'visibility': 'public',
        'subscriberCount': 1000,
        'memberCount': 500,
        'postCount': 2500,
        'viewer': {
          'subscribed': true,
          'member': false,
        },
      };

      final community = CommunityView.fromJson(json);

      expect(community.did, 'did:plc:community1');
      expect(community.name, 'test-community');
      expect(community.handle, 'test.coves.social');
      expect(community.displayName, 'Test Community');
      expect(community.description, 'A community for testing');
      expect(community.avatar, 'https://example.com/avatar.jpg');
      expect(community.visibility, 'public');
      expect(community.subscriberCount, 1000);
      expect(community.memberCount, 500);
      expect(community.postCount, 2500);
      expect(community.viewer, isNotNull);
      expect(community.viewer!.subscribed, true);
      expect(community.viewer!.member, false);
    });

    test('should parse minimal JSON with required fields only', () {
      final json = {
        'did': 'did:plc:community1',
        'name': 'test-community',
      };

      final community = CommunityView.fromJson(json);

      expect(community.did, 'did:plc:community1');
      expect(community.name, 'test-community');
      expect(community.handle, null);
      expect(community.displayName, null);
      expect(community.description, null);
      expect(community.avatar, null);
      expect(community.visibility, null);
      expect(community.subscriberCount, null);
      expect(community.memberCount, null);
      expect(community.postCount, null);
      expect(community.viewer, null);
    });

    test('should handle null optional fields', () {
      final json = {
        'did': 'did:plc:community1',
        'name': 'test-community',
        'handle': null,
        'displayName': null,
        'description': null,
        'avatar': null,
        'visibility': null,
        'subscriberCount': null,
        'memberCount': null,
        'postCount': null,
        'viewer': null,
      };

      final community = CommunityView.fromJson(json);

      expect(community.did, 'did:plc:community1');
      expect(community.name, 'test-community');
      expect(community.handle, null);
      expect(community.displayName, null);
      expect(community.description, null);
      expect(community.avatar, null);
      expect(community.visibility, null);
      expect(community.subscriberCount, null);
      expect(community.memberCount, null);
      expect(community.postCount, null);
      expect(community.viewer, null);
    });
  });

  group('CommunityViewerState', () {
    test('should parse with all fields', () {
      final json = {
        'subscribed': true,
        'member': true,
      };

      final viewer = CommunityViewerState.fromJson(json);

      expect(viewer.subscribed, true);
      expect(viewer.member, true);
    });

    test('should parse with false values', () {
      final json = {
        'subscribed': false,
        'member': false,
      };

      final viewer = CommunityViewerState.fromJson(json);

      expect(viewer.subscribed, false);
      expect(viewer.member, false);
    });

    test('should handle null values', () {
      final json = {
        'subscribed': null,
        'member': null,
      };

      final viewer = CommunityViewerState.fromJson(json);

      expect(viewer.subscribed, null);
      expect(viewer.member, null);
    });

    test('should handle missing fields', () {
      final json = <String, dynamic>{};

      final viewer = CommunityViewerState.fromJson(json);

      expect(viewer.subscribed, null);
      expect(viewer.member, null);
    });
  });

  group('CreatePostResponse', () {
    test('should parse valid JSON', () {
      final json = {
        'uri': 'at://did:plc:test/social.coves.community.post/123',
        'cid': 'bafyreicid123',
      };

      final response = CreatePostResponse.fromJson(json);

      expect(response.uri, 'at://did:plc:test/social.coves.community.post/123');
      expect(response.cid, 'bafyreicid123');
    });

    test('should be const constructible', () {
      const response = CreatePostResponse(
        uri: 'at://did:plc:test/post/123',
        cid: 'cid123',
      );

      expect(response.uri, 'at://did:plc:test/post/123');
      expect(response.cid, 'cid123');
    });
  });

  group('ExternalEmbedInput', () {
    test('should serialize complete JSON', () {
      const embed = ExternalEmbedInput(
        uri: 'https://example.com/article',
        title: 'Article Title',
        description: 'Article description',
        thumb: 'https://example.com/thumb.jpg',
      );

      final json = embed.toJson();

      expect(json['uri'], 'https://example.com/article');
      expect(json['title'], 'Article Title');
      expect(json['description'], 'Article description');
      expect(json['thumb'], 'https://example.com/thumb.jpg');
    });

    test('should serialize minimal JSON with only required fields', () {
      const embed = ExternalEmbedInput(
        uri: 'https://example.com/article',
      );

      final json = embed.toJson();

      expect(json['uri'], 'https://example.com/article');
      expect(json.containsKey('title'), false);
      expect(json.containsKey('description'), false);
      expect(json.containsKey('thumb'), false);
    });

    test('should be const constructible', () {
      const embed = ExternalEmbedInput(
        uri: 'https://example.com',
        title: 'Test',
      );

      expect(embed.uri, 'https://example.com');
      expect(embed.title, 'Test');
    });
  });

  group('SelfLabels', () {
    test('should serialize to JSON', () {
      const labels = SelfLabels(
        values: [
          SelfLabel(val: 'nsfw'),
          SelfLabel(val: 'spoiler'),
        ],
      );

      final json = labels.toJson();

      expect(json['values'], isA<List>());
      expect((json['values'] as List).length, 2);
      expect((json['values'] as List)[0]['val'], 'nsfw');
      expect((json['values'] as List)[1]['val'], 'spoiler');
    });

    test('should be const constructible', () {
      const labels = SelfLabels(
        values: [SelfLabel(val: 'nsfw')],
      );

      expect(labels.values.length, 1);
      expect(labels.values[0].val, 'nsfw');
    });
  });

  group('SelfLabel', () {
    test('should serialize to JSON', () {
      const label = SelfLabel(val: 'nsfw');

      final json = label.toJson();

      expect(json['val'], 'nsfw');
    });

    test('should be const constructible', () {
      const label = SelfLabel(val: 'spoiler');

      expect(label.val, 'spoiler');
    });
  });

  group('CreatePostRequest', () {
    test('should serialize complete request', () {
      final request = CreatePostRequest(
        community: 'did:plc:community1',
        title: 'Test Post',
        content: 'Post content here',
        embed: const ExternalEmbedInput(
          uri: 'https://example.com',
          title: 'Link Title',
        ),
        langs: ['en', 'es'],
        labels: const SelfLabels(values: [SelfLabel(val: 'nsfw')]),
      );

      final json = request.toJson();

      expect(json['community'], 'did:plc:community1');
      expect(json['title'], 'Test Post');
      expect(json['content'], 'Post content here');
      expect(json['embed'], isA<Map>());
      expect(json['langs'], ['en', 'es']);
      expect(json['labels'], isA<Map>());
    });

    test('should serialize minimal request with only required fields', () {
      final request = CreatePostRequest(
        community: 'did:plc:community1',
      );

      final json = request.toJson();

      expect(json['community'], 'did:plc:community1');
      expect(json.containsKey('title'), false);
      expect(json.containsKey('content'), false);
      expect(json.containsKey('embed'), false);
      expect(json.containsKey('langs'), false);
      expect(json.containsKey('labels'), false);
    });

    test('should not include empty langs array', () {
      final request = CreatePostRequest(
        community: 'did:plc:community1',
        langs: [],
      );

      final json = request.toJson();

      expect(json.containsKey('langs'), false);
    });
  });
}
