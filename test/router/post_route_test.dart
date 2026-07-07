import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:coves_flutter/screens/home/post_detail_loader.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Fake AuthProvider for testing (see test/widgets/feed_screen_test.dart)
class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => false;

  @override
  bool get isLoading => false;
}

// Fake EulaProvider that reports the EULA as already accepted so the
// router's redirect logic doesn't bounce us to /eula
class FakeEulaProvider extends EulaProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

// Fake CommunityGuidelinesProvider that reports guidelines as accepted
class FakeGuidelinesProvider extends CommunityGuidelinesProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

void main() {
  group('/post/:postUri route (cold path)', () {
    late GoRouter router;

    /// Pumps the app using the real production router from main.dart
    Future<void> pumpApp(WidgetTester tester) async {
      router = createRouter(
        FakeAuthProvider(),
        FakeEulaProvider(),
        FakeGuidelinesProvider(),
      );
      addTearDown(() => router.dispose());

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: FakeAuthProvider(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
    }

    testWidgets(
      'percent-encoded AT-URI reaches PostDetailLoader decoded exactly once',
      (tester) async {
        const atUri = 'at://did:plc:test/social.coves.community.post/abc123';

        await pumpApp(tester);

        // Navigate the way PostCard does: encode once, no extra (cold path).
        // pumpAndSettle lets the async route parsing finish and the fetch
        // fail against the test HTTP client (the loader stays in the tree)
        router.go('/post/${Uri.encodeComponent(atUri)}');
        await tester.pumpAndSettle();

        final loader = tester.widget<PostDetailLoader>(
          find.byType(PostDetailLoader),
        );
        expect(loader.postUri, atUri);
      },
    );

    testWidgets(
      'AT-URI containing a literal percent-sequence is not corrupted',
      (tester) async {
        // A did:web DID with a percent-encoded port legitimately contains
        // a %-sequence in the decoded AT-URI. A double decode would corrupt
        // it (%3A -> :) and cold-load the wrong URI.
        const atUri =
            'at://did:web:example.com%3A8443/social.coves.community.post/xyz';

        await pumpApp(tester);

        router.go('/post/${Uri.encodeComponent(atUri)}');
        await tester.pumpAndSettle();

        final loader = tester.widget<PostDetailLoader>(
          find.byType(PostDetailLoader),
        );
        expect(loader.postUri, atUri);
      },
    );

    testWidgets(
      'malformed percent sequence in deep link does not crash the builder',
      (tester) async {
        await pumpApp(tester);

        // Raw path segment foo%25zz decodes once (by go_router) to foo%zz.
        // A second Uri.decodeComponent would throw ArgumentError inside the
        // route builder - an unrecoverable grey screen from untrusted input.
        router.go('/post/foo%25zz');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // The once-decoded value is passed through; it's not an at:// URI,
        // so the loader short-circuits to the not-found state (no network)
        final loader = tester.widget<PostDetailLoader>(
          find.byType(PostDetailLoader),
        );
        expect(loader.postUri, 'foo%zz');
        expect(find.byType(NotFoundError), findsOneWidget);
        expect(find.text('Post Not Found'), findsOneWidget);
      },
    );
  });
}
