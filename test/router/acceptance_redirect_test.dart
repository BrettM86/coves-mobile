import 'package:coves_flutter/main.dart';
import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/community_guidelines_provider.dart';
import 'package:coves_flutter/providers/eula_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthenticatedProvider extends AuthProvider {
  _AuthenticatedProvider({required this.isAuthenticated});

  @override
  final bool isAuthenticated;

  @override
  bool get isLoading => false;
}

class _EulaProvider extends EulaProvider {
  _EulaProvider({required this.hasAccepted});

  @override
  final bool hasAccepted;

  @override
  bool get isLoading => false;
}

class _GuidelinesProvider extends CommunityGuidelinesProvider {
  _GuidelinesProvider({required this.hasAccepted});

  @override
  final bool hasAccepted;

  @override
  bool get isLoading => false;
}

void main() {
  group('acceptance redirects', () {
    Future<Uri> resolveRoute(
      WidgetTester tester,
      String location, {
      bool eulaAccepted = true,
      bool guidelinesAccepted = true,
      bool authenticated = true,
    }) async {
      final authProvider = _AuthenticatedProvider(
        isAuthenticated: authenticated,
      );
      final eulaProvider = _EulaProvider(hasAccepted: eulaAccepted);
      final guidelinesProvider = _GuidelinesProvider(
        hasAccepted: guidelinesAccepted,
      );
      final router = createRouter(
        authProvider,
        eulaProvider,
        guidelinesProvider,
      );
      addTearDown(() {
        router.dispose();
        authProvider.dispose();
        eulaProvider.dispose();
        guidelinesProvider.dispose();
      });

      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      );

      // Exercise go_router's complete redirect chain without building the
      // destination screens or starting their unrelated network requests.
      final matches = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            RouteInformation(uri: Uri.parse(location)),
            context,
          );
      expect(matches.isError, isFalse);
      return matches.uri;
    }

    testWidgets('accepted authenticated user reaches feed from EULA', (
      tester,
    ) async {
      expect(await resolveRoute(tester, '/eula'), Uri.parse('/feed'));
    });

    testWidgets('unaccepted EULA blocks authenticated feed access', (
      tester,
    ) async {
      expect(
        await resolveRoute(
          tester,
          '/feed',
          eulaAccepted: false,
          guidelinesAccepted: false,
        ),
        Uri.parse('/eula'),
      );
    });

    testWidgets('EULA acceptance advances to missing community guidelines', (
      tester,
    ) async {
      expect(
        await resolveRoute(tester, '/eula', guidelinesAccepted: false),
        Uri.parse('/community-guidelines'),
      );
    });

    testWidgets('missing community guidelines blocks authenticated feed', (
      tester,
    ) async {
      expect(
        await resolveRoute(tester, '/feed', guidelinesAccepted: false),
        Uri.parse('/community-guidelines'),
      );
    });

    for (final (
          description,
          authenticated,
          eulaAccepted,
          guidelinesAccepted,
          destination,
        )
        in [
          ('signed-in user returns to feed', true, true, true, '/feed'),
          ('pending sign-in returns to login', false, true, true, '/login'),
          ('missing EULA remains gated', true, false, false, '/eula'),
          (
            'missing guidelines remain gated',
            true,
            true,
            false,
            '/community-guidelines',
          ),
        ]) {
      testWidgets('OAuth callback: $description', (tester) async {
        // Synthetic opaque data only; the router must discard callback query
        // values without treating them as an application destination.
        final destinationUri = await resolveRoute(
          tester,
          'social.coves:/callback?opaque=test-fixture',
          authenticated: authenticated,
          eulaAccepted: eulaAccepted,
          guidelinesAccepted: guidelinesAccepted,
        );
        expect(
          destinationUri.path == destination &&
              destinationUri.scheme.isEmpty &&
              !destinationUri.hasQuery,
          isTrue,
          reason:
              'The callback must resolve to $destination without its query.',
        );
      });
    }

    for (final location in [
      '/eula?viewOnly=true',
      '/community-guidelines?viewOnly=true',
    ]) {
      testWidgets('accepted user can review $location', (tester) async {
        expect(await resolveRoute(tester, location), Uri.parse(location));
      });
    }
  });
}
