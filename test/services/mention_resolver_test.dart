import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/mention_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

void main() {
  late MockCovesApiService mockApiService;
  late ApiMentionResolver resolver;

  setUp(() {
    mockApiService = MockCovesApiService();
    resolver = ApiMentionResolver(mockApiService);
  });

  /// One failure per row, as the real CovesApiService raises them. A 400 is
  /// what the AppView returns for an unknown handle, a 404 for an unknown
  /// community; both mean "no such account" and resolve to null. Every other
  /// failure must reach the caller unchanged.
  Map<String, ApiException> failures() => {
    '400': ApiException('Unable to resolve handle', statusCode: 400),
    '404': NotFoundException('Community not found'),
    '401': AuthenticationException('Token expired'),
    '429': ApiException('Rate limited', statusCode: 429),
    '500': ServerException('Internal error', statusCode: 500),
    'network': NetworkException('Network error'),
    'parse': ApiException('Failed to parse server response'),
  };

  const expectedOutcomes = {
    '400': 'null',
    '404': 'null',
    '401': 'rethrew',
    '429': 'rethrew',
    '500': 'rethrew',
    'network': 'rethrew',
    'parse': 'rethrew',
  };

  /// Runs [lookup] and describes what came back: 'null', 'did <value>',
  /// 'rethrew' when [thrown] itself propagated, or the type of anything else
  Future<String> describeOutcome(
    Future<String?> Function() lookup,
    ApiException thrown,
  ) async {
    try {
      final did = await lookup();
      return did == null ? 'null' : 'did $did';
    } on Object catch (error) {
      return identical(error, thrown)
          ? 'rethrew'
          : 'threw ${error.runtimeType}';
    }
  }

  group('ApiMentionResolver.resolveHandle', () {
    test('returns the did the AppView resolves for the bare handle', () async {
      when(mockApiService.resolveHandle(handle: 'alice.coves.social'))
          .thenAnswer((_) async => 'did:plc:alice');

      expect(
        await resolver.resolveHandle('alice.coves.social'),
        'did:plc:alice',
      );
    });

    test('maps 400 and 404 to null and rethrows every other failure', () async {
      final outcomes = <String, String>{};
      for (final MapEntry(key: label, value: failure) in failures().entries) {
        when(mockApiService.resolveHandle(handle: 'alice.coves.social'))
            .thenAnswer((_) => Future<String>.error(failure));

        outcomes[label] = await describeOutcome(
          () => resolver.resolveHandle('alice.coves.social'),
          failure,
        );
      }

      expect(outcomes, expectedOutcomes);
    });
  });

  group('ApiMentionResolver.resolveCommunity', () {
    test('passes the exact bare name or name@origin to getCommunity and '
        'returns the community did', () async {
      when(mockApiService.getCommunity(community: 'gaming')).thenAnswer(
        (_) async => CommunityView(did: 'did:plc:gaming', name: 'gaming'),
      );
      when(mockApiService.getCommunity(community: 'gaming@coves.social'))
          .thenAnswer(
            (_) async => CommunityView(
              did: 'did:plc:gamingorigin',
              name: 'gaming',
              origin: 'coves.social',
            ),
          );

      expect(await resolver.resolveCommunity('gaming'), 'did:plc:gaming');
      expect(
        await resolver.resolveCommunity('gaming@coves.social'),
        'did:plc:gamingorigin',
      );
    });

    test('maps 400 and 404 to null and rethrows every other failure', () async {
      final outcomes = <String, String>{};
      for (final MapEntry(key: label, value: failure) in failures().entries) {
        when(mockApiService.getCommunity(community: 'gaming'))
            .thenAnswer((_) => Future<CommunityView>.error(failure));

        outcomes[label] = await describeOutcome(
          () => resolver.resolveCommunity('gaming'),
          failure,
        );
      }

      expect(outcomes, expectedOutcomes);
    });
  });
}
