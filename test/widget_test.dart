import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Fakes mirror test/router/post_route_test.dart: gates report accepted so the
// router doesn't redirect to /eula before MaterialApp settles.
class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => false;

  @override
  bool get isLoading => false;
}

class FakeEulaProvider extends EulaProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

class FakeGuidelinesProvider extends CommunityGuidelinesProvider {
  @override
  bool get hasAccepted => true;

  @override
  bool get isLoading => false;
}

void main() {
  testWidgets('CovesApp smoke test', (WidgetTester tester) async {
    final authProvider = FakeAuthProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<EulaProvider>(
            create: (_) => FakeEulaProvider(),
          ),
          ChangeNotifierProvider<CommunityGuidelinesProvider>(
            create: (_) => FakeGuidelinesProvider(),
          ),
          ChangeNotifierProvider(
            create: (_) => MultiFeedProvider(authProvider),
          ),
        ],
        child: const CovesApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
