import 'dart:async';

import 'package:coves_flutter/providers/community_subscription_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/community_join_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/test_mocks.dart';
import '../test_helpers/theme_pump.dart';

const _communityDid = 'did:plc:joinbuttoncommunity';
const _subscriptionFallback =
    'Could not update subscription. Please try again.';

void main() {
  late MockCovesApiService apiService;
  late MockAuthProvider authProvider;

  setUp(() {
    apiService = MockCovesApiService();
    authProvider = MockAuthProvider();
    when(authProvider.isAuthenticated).thenReturn(true);
  });

  /// Pumps a signed-in [CommunityJoinButton] backed by the real
  /// [CommunitySubscriptionProvider], makes subscribe fail with [error], taps
  /// Join, and settles the request and the SnackBar entrance animation.
  Future<void> tapJoinWhenSubscribeThrows(
    WidgetTester tester,
    Exception error,
  ) async {
    when(apiService.subscribeToCommunity(community: anyNamed('community')))
        .thenAnswer((_) async => throw error);

    await pumpUnderAppTheme(
      tester,
      ChangeNotifierProvider<CommunitySubscriptionProvider>(
        create: (_) => CommunitySubscriptionProvider(
          authProvider: authProvider,
          apiService: apiService,
        ),
        child: const Center(
          child: CommunityJoinButton(communityDid: _communityDid),
        ),
      ),
    );

    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    verify(apiService.subscribeToCommunity(community: _communityDid)).called(1);
    expect(find.byType(SnackBar), findsOneWidget);
  }

  /// Asserts the SnackBar reads exactly [text], reporting what it did read.
  void expectSnackBarText(WidgetTester tester, String text) {
    final shown = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ),
        )
        .map((widget) => widget.data)
        .toList();
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text(text)),
      findsOneWidget,
      reason: 'SnackBar showed $shown',
    );
  }

  group('CommunityJoinButton join failure SnackBar', () {
    testWidgets(
      'given subscribe throws a non-ApiException, when the user taps Join, '
      'then the SnackBar shows the subscription fallback and no developer '
      'text',
      (tester) async {
        await tapJoinWhenSubscribeThrows(
          tester,
          const FormatException('bad json'),
        );

        expectSnackBarText(tester, _subscriptionFallback);
        expect(find.textContaining('Unexpected error'), findsNothing);
        expect(find.textContaining('bad json'), findsNothing);
      },
    );

    testWidgets(
      'given subscribe throws AuthenticationException, when the user taps '
      'Join, then the SnackBar asks the user to sign in',
      (tester) async {
        const raw = 'Authentication failed. Token expired or invalid';
        await tapJoinWhenSubscribeThrows(tester, AuthenticationException(raw));

        expectSnackBarText(tester, 'Please sign in to continue.');
        expect(find.text(raw), findsNothing);
      },
    );

    testWidgets(
      'given subscribe throws a 4xx with a readable server message, when the '
      'user taps Join, then the SnackBar shows the server message',
      (tester) async {
        const raw = 'User is banned from this community';
        await tapJoinWhenSubscribeThrows(
          tester,
          ApiException(raw, statusCode: 403, errorCode: 'Banned'),
        );

        expectSnackBarText(tester, raw);
      },
    );

    testWidgets(
      'given subscribe throws a 4xx whose message is only its error code, '
      'when the user taps Join, then the SnackBar shows the subscription '
      'fallback',
      (tester) async {
        const raw = 'RateLimitExceeded';
        await tapJoinWhenSubscribeThrows(
          tester,
          ApiException(raw, statusCode: 429, errorCode: 'RateLimitExceeded'),
        );

        expectSnackBarText(tester, _subscriptionFallback);
        expect(find.text(raw), findsNothing);
      },
    );

    testWidgets(
      'given subscribe throws a 4xx whose message is an HTML body, when the '
      'user taps Join, then the SnackBar shows the subscription fallback',
      (tester) async {
        const raw = '<html><body>Bad Gateway</body></html>';
        await tapJoinWhenSubscribeThrows(
          tester,
          ApiException(raw, statusCode: 400),
        );

        expectSnackBarText(tester, _subscriptionFallback);
        expect(find.text(raw), findsNothing);
      },
    );

    testWidgets(
      'given subscribe throws ServerException, when the user taps Join, '
      'then the SnackBar shows the server error message',
      (tester) async {
        const raw = 'upstream exploded';
        await tapJoinWhenSubscribeThrows(
          tester,
          ServerException(raw, statusCode: 502),
        );

        expectSnackBarText(tester, 'Server error. Please try again later.');
        expect(find.text(raw), findsNothing);
      },
    );

    testWidgets('given the button unmounts while subscribe is in flight, when '
        'subscribe then fails, then the SnackBar still shows the failure', (
      tester,
    ) async {
      final request = Completer<String>();
      when(apiService.subscribeToCommunity(community: anyNamed('community')))
          .thenAnswer((_) => request.future);
      final showButton = ValueNotifier<bool>(true);
      addTearDown(showButton.dispose);

      await pumpUnderAppTheme(
        tester,
        ChangeNotifierProvider<CommunitySubscriptionProvider>(
          create: (_) => CommunitySubscriptionProvider(
            authProvider: authProvider,
            apiService: apiService,
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: showButton,
            builder: (context, show, _) => show
                ? const Center(
                    child: CommunityJoinButton(communityDid: _communityDid),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      );

      await tester.tap(find.text('Join'));
      await tester.pump();
      showButton.value = false;
      await tester.pump();
      expect(find.byType(CommunityJoinButton), findsNothing);

      request.completeError(const FormatException('bad json'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expectSnackBarText(tester, _subscriptionFallback);
    });
  });

  group('CommunityJoinButton leave failure SnackBar', () {
    testWidgets(
      'given unsubscribe throws NotFoundException, when the user taps '
      'Joined, then the SnackBar shows the subscription fallback rather than '
      'content-removed copy',
      (tester) async {
        when(
          apiService.unsubscribeFromCommunity(community: anyNamed('community')),
        ).thenAnswer(
          (_) async => throw NotFoundException(
            'subscription not found',
            errorCode: 'NotFound',
          ),
        );

        await pumpUnderAppTheme(
          tester,
          ChangeNotifierProvider<CommunitySubscriptionProvider>(
            create: (_) =>
                CommunitySubscriptionProvider(
                  authProvider: authProvider,
                  apiService: apiService,
                )..setInitialSubscriptionState(
                  communityDid: _communityDid,
                  isSubscribed: true,
                ),
            child: const Center(
              child: CommunityJoinButton(communityDid: _communityDid),
            ),
          ),
        );

        await tester.tap(find.text('Joined'));
        await tester.pumpAndSettle();

        verify(apiService.unsubscribeFromCommunity(community: _communityDid))
            .called(1);
        expectSnackBarText(tester, _subscriptionFallback);
        expect(find.textContaining('Content not found'), findsNothing);
        expect(find.text('Joined'), findsOneWidget);
      },
    );
  });
}
