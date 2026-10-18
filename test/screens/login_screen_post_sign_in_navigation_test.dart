import 'dart:async';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/models/post_get_result.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/screens/auth/login_screen.dart';
import 'package:coves_flutter/screens/home/main_shell_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/screens/landing_screen.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/services/coves_auth_service.dart';
import 'package:coves_flutter/services/post_change_broadcast.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/sign_in_flow_fakes.dart';
import '../test_helpers/test_mocks.dart';

// Where LoginScreen goes after the sign-in it started. Pushed over a route
// the user was on, it pops back there. Pushed from the landing screen it
// goes to /feed, since there is nothing to return to. A cancelled or failed
// sign-in navigates nowhere. Runs through the production router so its
// redirect and its refresh on auth changes take part.

const _signedInDid = 'did:plc:alice';
const _missingPostUri = 'at://did:plc:author/social.coves.community.post/gone';

/// The production router over the providers /, /login, /feed and a cold
/// /post resolve.
class _LoginHarness {
  _LoginHarness() {
    feeds = IdleFeedProvider(auth, apiService: api);
    router = createRouter(auth, eula, guidelines);
    // A cold /post that resolves as not found renders a static screen,
    // keeping the comments cache and its sign-in handling out of these
    // navigation tests. Mockito cannot build a placeholder of the sealed
    // result type while stubbing.
    // The cold-load loader stamps the post with the viewer's authority.
    when(api.getViewerAuthority()).thenAnswer((_) async => false);
    provideDummy<PostGetResult>(const PostGetNotFound(_missingPostUri));
    when(api.getPost(any))
        .thenAnswer((_) async => const PostGetNotFound(_missingPostUri));
  }

  final auth = GatedSignInAuthProvider();
  final eula = AcceptedEulaProvider();
  final guidelines = AcceptedGuidelinesProvider();
  final api = MockCovesApiService();
  late final MultiFeedProvider feeds;
  late final GoRouter router;

  Widget app() {
    return MultiProvider(
      providers: [
        Provider<PostChangeBroadcast>.value(value: PostChangeBroadcast()),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<MultiFeedProvider>.value(value: feeds),
        Provider<CovesApiService>.value(value: api),
        viewerAuthorityRegistration(auth: auth, apiService: api),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  String get location => router.routerDelegate.currentConfiguration.uri.path;

  /// The matched location of each route on the stack, bottom first.
  List<String> get stack => router.routerDelegate.currentConfiguration.matches
      .map((match) => match.matchedLocation)
      .toList();

  /// The binding unmounts the tree before tear-downs run, so these dispose
  /// nothing a mounted widget still holds.
  void disposeOnTearDown() {
    addTearDown(() {
      router.dispose();
      feeds.dispose();
      guidelines.dispose();
      eula.dispose();
      auth.dispose();
    });
  }
}

/// A router over /feed and /login whose pop throws an Exception, standing in
/// for a navigation failure after a successful sign-in. go_router's own
/// navigation failures are Errors, so the production router cannot put an
/// Exception on that path.
class _PopThrowsExceptionRouter extends GoRouter {
  _PopThrowsExceptionRouter(ValueListenable<RoutingConfig> routingConfig)
    : super.routingConfig(
        routingConfig: routingConfig,
        initialLocation: '/feed',
      );

  @override
  void pop<T extends Object?>([T? result]) {
    throw Exception('navigation failed');
  }
}

/// Forces the phone layout. A width just under the tablet breakpoint keeps
/// the login screen's copy from overflowing in the test font, whose glyphs
/// are wider than the app's.
void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(590, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Fails if an exception was reported or an error widget is in the tree.
void _expectNoErrors(WidgetTester tester, String phase) {
  expect(tester.takeException(), isNull, reason: 'exception $phase');
  expect(
    find.byType(ErrorWidget, skipOffstage: false),
    findsNothing,
    reason: 'error widget $phase',
  );
}

/// Opens /feed and pushes /login over it, as a sign-in prompt does.
Future<void> _pushLoginOverFeed(
  WidgetTester tester,
  _LoginHarness harness,
) async {
  await tester.pumpWidget(harness.app());
  harness.router.go('/feed');
  await tester.pumpAndSettle();
  expect(find.byType(MainShellScreen), findsOneWidget);

  unawaited(harness.router.push('/login'));
  await tester.pumpAndSettle();
  _expectNoErrors(tester, 'after pushing /login');
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(harness.stack, ['/feed', '/login']);
  expect(harness.router.canPop(), isTrue);
}

/// Submits a handle on the visible login screen and ends the OAuth step
/// with [finishOAuth], pumping frames between the provider's loading
/// notification and its final one.
Future<void> _submitSignIn(
  WidgetTester tester,
  _LoginHarness harness,
  void Function() finishOAuth,
) async {
  await tester.enterText(find.byType(TextFormField), 'alice.test');
  await tester.tap(find.text('Sign in'));
  await tester.pump();
  expect(harness.auth.isAwaitingOAuth, isTrue);
  expect(harness.auth.isLoading, isTrue);
  await tester.pump(const Duration(milliseconds: 100));
  _expectNoErrors(tester, 'while the sign-in is waiting on OAuth');

  finishOAuth();
  await tester.pump();
  _expectNoErrors(tester, 'on the frame after OAuth ended');
  await tester.pumpAndSettle();
  _expectNoErrors(tester, 'after the sign-in settled');
}

void main() {
  testWidgets('given /login pushed over a post pushed over /feed, when sign-in '
      'succeeds, then the login route pops back to that post with the stack '
      'under it unchanged', (tester) async {
    _usePhoneViewport(tester);
    final harness = _LoginHarness()..disposeOnTearDown();
    final postLocation = '/post/${Uri.encodeComponent(_missingPostUri)}';
    await tester.pumpWidget(harness.app());
    harness.router.go('/feed');
    await tester.pumpAndSettle();
    unawaited(harness.router.push(postLocation));
    await tester.pumpAndSettle();
    expect(find.byType(NotFoundError), findsOneWidget);
    final postState = tester.state(find.byType(PostDetailLoader));

    unawaited(harness.router.push('/login'));
    await tester.pumpAndSettle();
    _expectNoErrors(tester, 'after pushing /login');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(harness.stack, ['/feed', postLocation, '/login']);

    await _submitSignIn(
      tester,
      harness,
      () => harness.auth.completeOAuth(_signedInDid),
    );

    // The push's Future is not asserted: go_router's codec rebuilds pushed
    // routes with fresh completers on every refresh, orphaning it.
    expect(harness.auth.did, _signedInDid);
    expect(find.byType(LoginScreen, skipOffstage: false), findsNothing);
    expect(
      find.byType(PostDetailLoader),
      findsOneWidget,
      reason:
          'the login route must pop back to the route the user signed in '
          'from, not navigate to /feed',
    );
    expect(tester.state(find.byType(PostDetailLoader)), same(postState));
    expect(
      ModalRoute.of(tester.element(find.byType(PostDetailLoader)))?.isCurrent,
      isTrue,
    );
    expect(harness.stack, ['/feed', postLocation]);
    expect(harness.router.canPop(), isTrue);
    expect(find.byType(MainShellScreen, skipOffstage: false), findsOneWidget);
    _expectNoErrors(tester, 'at the end');
  });

  testWidgets(
    'given /login pushed from the landing screen, when sign-in succeeds, '
    'then the app lands on /feed, not back on the landing screen',
    (tester) async {
      _usePhoneViewport(tester);
      final harness = _LoginHarness()..disposeOnTearDown();
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(find.byType(LandingScreen), findsOneWidget);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      _expectNoErrors(tester, 'after opening /login from the landing screen');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(harness.router.canPop(), isTrue);

      await _submitSignIn(
        tester,
        harness,
        () => harness.auth.completeOAuth(_signedInDid),
      );

      expect(harness.auth.did, _signedInDid);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(LandingScreen, skipOffstage: false), findsNothing);
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(harness.location, '/feed');
      expect(harness.router.canPop(), isFalse);
    },
  );

  for (final (outcome, error, message) in [
    ('is cancelled', const SignInCancelledException(), 'Sign in cancelled.'),
    (
      'fails',
      Exception('OAuth failed'),
      'Sign in failed. Please try again later.',
    ),
  ]) {
    testWidgets(
      'given /login pushed over /feed, when the sign-in $outcome, then the '
      'login screen stays',
      (tester) async {
        _usePhoneViewport(tester);
        final harness = _LoginHarness()..disposeOnTearDown();
        await _pushLoginOverFeed(tester, harness);
        final loginState = tester.state(find.byType(LoginScreen));

        await _submitSignIn(
          tester,
          harness,
          () => harness.auth.failOAuth(error),
        );

        expect(harness.auth.did, isNull);
        expect(find.text(message), findsOneWidget);
        expect(
          find.byType(LoginScreen),
          findsOneWidget,
          reason: 'a sign-in that $outcome must not navigate',
        );
        expect(tester.state(find.byType(LoginScreen)), same(loginState));
        expect(
          ModalRoute.of(tester.element(find.byType(LoginScreen)))?.isCurrent,
          isTrue,
        );
        expect(
          harness.stack,
          ['/feed', '/login'],
          reason:
              'a sign-in that $outcome must leave the route stack as it was',
        );
        expect(harness.router.canPop(), isTrue);
      },
    );
  }

  testWidgets(
    'given /login pushed over /feed, when sign-in succeeds and leaving the '
    'login route throws an Exception, then it surfaces as an uncaught error, '
    'not as a failed sign-in',
    (tester) async {
      _usePhoneViewport(tester);
      final auth = GatedSignInAuthProvider();
      final routingConfig = ValueNotifier(
        RoutingConfig(
          routes: [
            GoRoute(
              path: '/feed',
              builder: (context, state) => const Scaffold(),
            ),
            GoRoute(
              path: '/login',
              builder: (context, state) => const LoginScreen(),
            ),
          ],
        ),
      );
      final router = _PopThrowsExceptionRouter(routingConfig);
      addTearDown(() {
        router.dispose();
        routingConfig.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      unawaited(router.push('/login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'alice.test');
      // The sign-in runs in the zone of the tap that starts it, so an error
      // it leaves uncaught lands here instead of failing the test.
      final uncaughtErrors = <Object>[];
      await runZonedGuarded(
        () => tester.tap(find.text('Sign in')),
        (error, stackTrace) => uncaughtErrors.add(error),
      );
      await tester.pump();
      expect(auth.isAwaitingOAuth, isTrue);
      auth.completeOAuth(_signedInDid);
      await tester.pumpAndSettle();

      expect(auth.did, _signedInDid);
      expect(
        find.text('Sign in failed. Please try again later.'),
        findsNothing,
        reason: 'the sign-in succeeded; only leaving the login route failed',
      );
      expect(uncaughtErrors, [
        isA<Exception>().having(
          (exception) => exception.toString(),
          'message',
          contains('navigation failed'),
        ),
      ], reason: 'a navigation failure must reach the uncaught-error handlers');
    },
  );
}
