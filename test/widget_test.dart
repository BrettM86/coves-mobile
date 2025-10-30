import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/feed_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('CovesApp smoke test', (WidgetTester tester) async {
    // Create auth provider
    final authProvider = AuthProvider();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => FeedProvider(authProvider)),
        ],
        child: const CovesApp(),
      ),
    );

    // Allow the router to initialize
    await tester.pumpAndSettle();

    // Verify that the app builds without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
