import 'dart:async';

import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/block_provider.dart';
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

  group('BlockProvider', () {
    const userDid = 'did:plc:blockeduser';
    const communityDid = 'did:plc:blockedcommunity';

    late FakeAuthProvider authProvider;
    late MockCovesApiService mockApiService;
    late BlockProvider provider;
    late int notifyCount;

    setUp(() {
      authProvider = FakeAuthProvider();
      mockApiService = MockCovesApiService();

      // Default stubs: API calls succeed
      when(
        mockApiService.blockUser(actor: anyNamed('actor')),
      ).thenAnswer((_) async => 'at://$userDid/social.coves.block/1');
      when(
        mockApiService.unblockUser(actor: anyNamed('actor')),
      ).thenAnswer((_) async {});
      when(
        mockApiService.blockCommunity(community: anyNamed('community')),
      ).thenAnswer((_) async => 'at://$communityDid/social.coves.block/1');
      when(
        mockApiService.unblockCommunity(community: anyNamed('community')),
      ).thenAnswer((_) async {});

      provider = BlockProvider(
        apiService: mockApiService,
        authProvider: authProvider,
      );
      notifyCount = 0;
      provider.addListener(() => notifyCount++);
    });

    tearDown(() {
      provider.dispose();
      authProvider.dispose();
    });

    test('rejects invalid DIDs', () async {
      await expectLater(
        provider.toggleUserBlock(userDid: 'not-a-did'),
        throwsA(isA<ApiException>()),
      );
      verifyNever(mockApiService.blockUser(actor: anyNamed('actor')));
    });

    test('toggle-then-refetch: user toggle beats a stale server seed',
        () async {
      await provider.toggleUserBlock(userDid: userDid);
      expect(provider.isUserBlocked(userDid), isTrue);

      // A stale profile refetch reports the pre-toggle state
      provider.setInitialUserBlockState(userDid: userDid, isBlocked: false);

      expect(provider.isUserBlocked(userDid), isTrue);
    });

    test('spinner settles: pending clears and notifies on completion',
        () async {
      final completer = Completer<String>();
      when(
        mockApiService.blockUser(actor: anyNamed('actor')),
      ).thenAnswer((_) => completer.future);

      final future = provider.toggleUserBlock(userDid: userDid);

      expect(provider.isUserBlockPending(userDid), isTrue);
      final notificationsMidFlight = notifyCount;

      completer.complete('at://$userDid/social.coves.block/1');
      await future;

      expect(provider.isUserBlockPending(userDid), isFalse);
      expect(
        notifyCount,
        greaterThan(notificationsMidFlight),
        reason: 'completion must notify so pending spinners are rebuilt',
      );
    });

    test('rollback: failed toggle reverts, notifies, and unblocks seeds',
        () async {
      when(
        mockApiService.blockUser(actor: anyNamed('actor')),
      ).thenThrow(ApiException('Server error', statusCode: 500));

      await expectLater(
        provider.toggleUserBlock(userDid: userDid),
        throwsA(isA<ApiException>()),
      );

      expect(provider.isUserBlocked(userDid), isFalse);
      expect(notifyCount, greaterThan(0));

      // The failed toggle must not stay authoritative: a later server
      // seed applies again (pins the toggled-set rollback fix)
      provider.setInitialUserBlockState(userDid: userDid, isBlocked: true);
      expect(provider.isUserBlocked(userDid), isTrue);
    });

    test('seed during in-flight toggle does not clobber optimistic state',
        () async {
      final completer = Completer<String>();
      when(
        mockApiService.blockUser(actor: anyNamed('actor')),
      ).thenAnswer((_) => completer.future);

      final future = provider.toggleUserBlock(userDid: userDid);
      expect(provider.isUserBlocked(userDid), isTrue);

      provider.setInitialUserBlockState(userDid: userDid, isBlocked: false);
      expect(provider.isUserBlocked(userDid), isTrue);

      completer.complete('at://$userDid/social.coves.block/1');
      await future;

      // Successful toggle keeps authority even after completion
      provider.setInitialUserBlockState(userDid: userDid, isBlocked: false);
      expect(provider.isUserBlocked(userDid), isTrue);
    });

    test('seed freshness: non-toggled seeds stay refreshable', () {
      // e.g. a block made from another device shows up on refetch
      provider.setInitialUserBlockState(userDid: userDid, isBlocked: false);
      expect(provider.isUserBlocked(userDid), isFalse);

      provider.setInitialUserBlockState(userDid: userDid, isBlocked: true);
      expect(provider.isUserBlocked(userDid), isTrue);
    });

    test('seed notifies only when the stored value changes', () {
      provider.setInitialUserBlockState(userDid: userDid, isBlocked: true);
      final notificationsAfterFirstSeed = notifyCount;

      provider.setInitialUserBlockState(userDid: userDid, isBlocked: true);
      expect(notifyCount, notificationsAfterFirstSeed);

      provider.setInitialUserBlockState(userDid: userDid, isBlocked: false);
      expect(notifyCount, notificationsAfterFirstSeed + 1);
    });

    test('sign-out lifecycle: clears toggle authority so seeds apply again',
        () async {
      await provider.toggleUserBlock(userDid: userDid);
      expect(provider.isUserBlocked(userDid), isTrue);

      authProvider.setAuthenticated(value: false);
      expect(provider.isUserBlocked(userDid), isFalse);

      // Toggle authority was cleared: a fresh seed applies
      provider.setInitialUserBlockState(userDid: userDid, isBlocked: true);
      expect(provider.isUserBlocked(userDid), isTrue);
    });

    test('concurrent toggle while pending makes no second API call', () async {
      final completer = Completer<String>();
      when(
        mockApiService.blockUser(actor: anyNamed('actor')),
      ).thenAnswer((_) => completer.future);

      final first = provider.toggleUserBlock(userDid: userDid);
      final second = await provider.toggleUserBlock(userDid: userDid);

      // Second call returns current optimistic state without toggling
      expect(second, isTrue);

      completer.complete('at://$userDid/social.coves.block/1');
      await first;

      verify(mockApiService.blockUser(actor: anyNamed('actor'))).called(1);
      verifyNever(mockApiService.unblockUser(actor: anyNamed('actor')));
      expect(provider.isUserBlocked(userDid), isTrue);
    });

    group('community blocks', () {
      test('toggled community beats a stale server seed', () async {
        await provider.toggleCommunityBlock(communityDid: communityDid);
        expect(provider.isCommunityBlocked(communityDid), isTrue);

        provider.setInitialCommunityBlockState(
          communityDid: communityDid,
          isBlocked: false,
        );

        expect(provider.isCommunityBlocked(communityDid), isTrue);
      });

      test('non-toggled seeds stay refreshable and notify on change', () {
        provider.setInitialCommunityBlockState(
          communityDid: communityDid,
          isBlocked: true,
        );
        expect(provider.isCommunityBlocked(communityDid), isTrue);
        final notificationsAfterFirstSeed = notifyCount;

        // Same value: no notification
        provider.setInitialCommunityBlockState(
          communityDid: communityDid,
          isBlocked: true,
        );
        expect(notifyCount, notificationsAfterFirstSeed);

        // Fresher snapshot: applies and notifies
        provider.setInitialCommunityBlockState(
          communityDid: communityDid,
          isBlocked: false,
        );
        expect(provider.isCommunityBlocked(communityDid), isFalse);
        expect(notifyCount, notificationsAfterFirstSeed + 1);
      });

      test('failed community toggle reverts and unblocks seeds', () async {
        when(
          mockApiService.blockCommunity(community: anyNamed('community')),
        ).thenThrow(ApiException('Server error', statusCode: 500));

        await expectLater(
          provider.toggleCommunityBlock(communityDid: communityDid),
          throwsA(isA<ApiException>()),
        );

        expect(provider.isCommunityBlocked(communityDid), isFalse);

        provider.setInitialCommunityBlockState(
          communityDid: communityDid,
          isBlocked: true,
        );
        expect(provider.isCommunityBlocked(communityDid), isTrue);
      });
    });
  });
}
