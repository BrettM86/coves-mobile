import 'dart:async';

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/test_mocks.dart';

/// Fake AuthProvider with controllable auth state and real ChangeNotifier
/// behavior (the provider under test listens for sign-out).
class FakeAuthProvider extends AuthProvider {
  FakeAuthProvider({bool isAuthenticated = true})
    : _isAuthenticated = isAuthenticated;

  bool _isAuthenticated;

  @override
  bool get isAuthenticated => _isAuthenticated;

  void setAuthenticated({required bool value}) {
    _isAuthenticated = value;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommunitySubscriptionProvider', () {
    const did = 'did:plc:community1';
    const otherDid = 'did:plc:community2';

    late FakeAuthProvider authProvider;
    late MockCovesApiService mockApiService;
    late CommunitySubscriptionProvider provider;
    late int notifyCount;

    setUp(() {
      authProvider = FakeAuthProvider();
      mockApiService = MockCovesApiService();

      // Default stubs: API calls succeed, no subscribed communities
      when(
        mockApiService.subscribeToCommunity(community: anyNamed('community')),
      ).thenAnswer((_) async => 'at://$did/social.coves.subscription/1');
      when(
        mockApiService.unsubscribeFromCommunity(
          community: anyNamed('community'),
        ),
      ).thenAnswer((_) async {});
      when(
        mockApiService.listCommunities(
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          sort: anyNamed('sort'),
          subscribed: anyNamed('subscribed'),
        ),
      ).thenAnswer((_) async => CommunitiesResponse(communities: []));

      provider = CommunitySubscriptionProvider(
        authProvider: authProvider,
        apiService: mockApiService,
      );
      notifyCount = 0;
      provider.addListener(() => notifyCount++);
    });

    tearDown(() {
      provider.dispose();
      authProvider.dispose();
    });

    test('toggle-then-refetch: user toggle beats a stale server seed',
        () async {
      await provider.toggleSubscription(communityDid: did);
      expect(provider.isSubscribed(did), isTrue);

      // A refetch racing the firehose reports the pre-toggle state
      provider.setInitialSubscriptionState(
        communityDid: did,
        isSubscribed: false,
      );

      expect(provider.isSubscribed(did), isTrue);
    });

    test('spinner settles: pending clears and notifies on completion',
        () async {
      final completer = Completer<String>();
      when(
        mockApiService.subscribeToCommunity(community: anyNamed('community')),
      ).thenAnswer((_) => completer.future);

      final future = provider.toggleSubscription(communityDid: did);

      expect(provider.isPending(did), isTrue);
      final notificationsMidFlight = notifyCount;

      completer.complete('at://$did/social.coves.subscription/1');
      await future;

      expect(provider.isPending(did), isFalse);
      expect(
        notifyCount,
        greaterThan(notificationsMidFlight),
        reason: 'completion must notify so pending spinners are rebuilt',
      );
    });

    test('rollback: failed toggle reverts, notifies, and unblocks seeds',
        () async {
      when(
        mockApiService.subscribeToCommunity(community: anyNamed('community')),
      ).thenThrow(ApiException('Server error', statusCode: 500));

      await expectLater(
        provider.toggleSubscription(communityDid: did),
        throwsA(isA<ApiException>()),
      );

      expect(provider.isSubscribed(did), isFalse);
      expect(notifyCount, greaterThan(0));

      // The failed toggle must not stay authoritative: a later server
      // seed applies again (pins the _userToggled rollback fix)
      provider.setInitialSubscriptionState(
        communityDid: did,
        isSubscribed: true,
      );
      expect(provider.isSubscribed(did), isTrue);
    });

    test('seed during in-flight toggle does not clobber optimistic state',
        () async {
      final completer = Completer<String>();
      when(
        mockApiService.subscribeToCommunity(community: anyNamed('community')),
      ).thenAnswer((_) => completer.future);

      final future = provider.toggleSubscription(communityDid: did);
      expect(provider.isSubscribed(did), isTrue);

      provider.setInitialSubscriptionState(
        communityDid: did,
        isSubscribed: false,
      );
      expect(provider.isSubscribed(did), isTrue);

      completer.complete('at://$did/social.coves.subscription/1');
      await future;

      expect(provider.isSubscribed(did), isTrue);
    });

    test('seed freshness: non-toggled seeds stay refreshable', () {
      provider.setInitialSubscriptionState(
        communityDid: did,
        isSubscribed: false,
      );
      expect(provider.isSubscribed(did), isFalse);

      provider.setInitialSubscriptionState(
        communityDid: did,
        isSubscribed: true,
      );
      expect(provider.isSubscribed(did), isTrue);
    });

    test('sign-out lifecycle: clears toggle authority so seeds apply again',
        () async {
      await provider.toggleSubscription(communityDid: did);
      expect(provider.isSubscribed(did), isTrue);

      authProvider.setAuthenticated(value: false);
      expect(provider.isSubscribed(did), isFalse);

      // Toggle authority was cleared: a fresh seed applies
      provider.setInitialSubscriptionState(
        communityDid: did,
        isSubscribed: true,
      );
      expect(provider.isSubscribed(did), isTrue);
    });

    test('loadSubscribedCommunities respects user-toggled state', () async {
      // User is subscribed to both communities server-side
      provider.setInitialSubscriptionState(
        communityDid: did,
        isSubscribed: true,
      );

      // User unsubscribes from the first community
      await provider.toggleSubscription(communityDid: did);
      expect(provider.isSubscribed(did), isFalse);

      // A refetch (firehose lag) still lists both as subscribed
      when(
        mockApiService.listCommunities(
          limit: anyNamed('limit'),
          cursor: anyNamed('cursor'),
          sort: anyNamed('sort'),
          subscribed: anyNamed('subscribed'),
        ),
      ).thenAnswer(
        (_) async => CommunitiesResponse(
          communities: [
            CommunityView(did: did, name: 'community1'),
            CommunityView(did: otherDid, name: 'community2'),
          ],
        ),
      );

      await provider.loadSubscribedCommunities();

      // Toggled DID keeps the user's state; the other seeds normally
      expect(provider.isSubscribed(did), isFalse);
      expect(provider.isSubscribed(otherDid), isTrue);
    });

    test('concurrent toggle while pending makes no second API call', () async {
      final completer = Completer<String>();
      when(
        mockApiService.subscribeToCommunity(community: anyNamed('community')),
      ).thenAnswer((_) => completer.future);

      final first = provider.toggleSubscription(communityDid: did);
      final second = await provider.toggleSubscription(communityDid: did);

      // Second call returns current optimistic state without toggling
      expect(second, isTrue);

      completer.complete('at://$did/social.coves.subscription/1');
      await first;

      verify(
        mockApiService.subscribeToCommunity(community: anyNamed('community')),
      ).called(1);
      verifyNever(
        mockApiService.unsubscribeFromCommunity(
          community: anyNamed('community'),
        ),
      );
      expect(provider.isSubscribed(did), isTrue);
    });
  });
}
