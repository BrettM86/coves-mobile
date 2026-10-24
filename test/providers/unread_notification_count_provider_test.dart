import 'dart:async';

import 'package:coves_flutter/providers/unread_notification_count_provider.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../test_helpers/fake_providers.dart';
import '../test_helpers/test_mocks.dart';

void _resumeBinding(WidgetTester tester) {
  switch (tester.binding.lifecycleState) {
    case null:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.resumed:
      break;
    case AppLifecycleState.inactive:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.hidden:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.paused:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.detached:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void _backgroundBinding(WidgetTester tester, {required bool paused}) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  if (paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnreadNotificationCountProvider', () {
    late FakeAuthProvider auth;
    late MockCovesApiService api;

    setUp(() {
      auth = FakeAuthProvider();
      api = MockCovesApiService();
    });

    tearDown(() => auth.dispose());

    testWidgets('B2 signed-in construction fetches the unread count once', (
      tester,
    ) async {
      _resumeBinding(tester);
      auth.setSignedInDid('did:plc:alice');
      when(api.getUnreadCount()).thenAnswer((_) async => 4);
      final provider = UnreadNotificationCountProvider(
        apiService: api,
        authProvider: auth,
      );
      try {
        await tester.pump();
        verify(api.getUnreadCount()).called(1);
        expect(provider.count, 4);
      } finally {
        provider.dispose();
        _resumeBinding(tester);
      }
      verifyNever(api.dispose());
    });

    testWidgets('B2 signed-out refresh and resume wait for sign-in', (
      tester,
    ) async {
      _resumeBinding(tester);
      when(api.getUnreadCount()).thenAnswer((_) async => 6);
      final provider = UnreadNotificationCountProvider(
        apiService: api,
        authProvider: auth,
      );
      try {
        await tester.pump();
        verifyNever(api.getUnreadCount());
        await provider.refresh();
        verifyNever(api.getUnreadCount());
        _backgroundBinding(tester, paused: true);
        _resumeBinding(tester);
        await tester.pump();
        verifyNever(api.getUnreadCount());

        auth.setSignedInDid('did:plc:alice');
        await tester.pump();
        verify(api.getUnreadCount()).called(1);
        expect(provider.count, 6);
        await tester.pump(const Duration(seconds: 30));
        verify(api.getUnreadCount()).called(1);
        await tester.pump(const Duration(seconds: 30));
        verify(api.getUnreadCount()).called(1);
      } finally {
        provider.dispose();
        _resumeBinding(tester);
      }
    });

    testWidgets('B3 resumed session polls at 30 and 60 seconds', (
      tester,
    ) async {
      _resumeBinding(tester);
      auth.setSignedInDid('did:plc:alice');
      when(api.getUnreadCount()).thenAnswer((_) async => 4);
      final provider = UnreadNotificationCountProvider(
        apiService: api,
        authProvider: auth,
      );
      try {
        await tester.pump();
        verify(api.getUnreadCount()).called(1);
        await tester.pump(const Duration(seconds: 30));
        verify(api.getUnreadCount()).called(1);
        await tester.pump(const Duration(seconds: 30));
        verify(api.getUnreadCount()).called(1);
      } finally {
        provider.dispose();
        _resumeBinding(tester);
      }
    });

    for (final paused in [false, true]) {
      final stateName = paused ? 'paused' : 'hidden';
      testWidgets('B3 $stateName stops polling and resumes immediately', (
        tester,
      ) async {
        _resumeBinding(tester);
        auth.setSignedInDid('did:plc:alice');
        when(api.getUnreadCount()).thenAnswer((_) async => 4);
        final provider = UnreadNotificationCountProvider(
          apiService: api,
          authProvider: auth,
        );
        try {
          await tester.pump();
          verify(api.getUnreadCount()).called(1);
          _backgroundBinding(tester, paused: paused);
          await tester.pump(const Duration(seconds: 90));
          verifyNever(api.getUnreadCount());

          _resumeBinding(tester);
          await tester.pump();
          verify(api.getUnreadCount()).called(1);
          await tester.pump(const Duration(seconds: 30));
          verify(api.getUnreadCount()).called(1);
        } finally {
          provider.dispose();
          _resumeBinding(tester);
        }
      });

      testWidgets('B3 sign-in while $stateName waits until resume', (
        tester,
      ) async {
        _resumeBinding(tester);
        when(api.getUnreadCount()).thenAnswer((_) async => 4);
        final provider = UnreadNotificationCountProvider(
          apiService: api,
          authProvider: auth,
        );
        try {
          _backgroundBinding(tester, paused: paused);
          auth.setSignedInDid('did:plc:alice');
          await tester.pump();
          verify(api.getUnreadCount()).called(1);
          await tester.pump(const Duration(seconds: 90));
          verifyNever(api.getUnreadCount());

          _resumeBinding(tester);
          await tester.pump();
          verify(api.getUnreadCount()).called(1);
          await tester.pump(const Duration(seconds: 30));
          verify(api.getUnreadCount()).called(1);
        } finally {
          provider.dispose();
          _resumeBinding(tester);
        }
      });
    }

    testWidgets('B4 sign-out clears count synchronously and stops polling', (
      tester,
    ) async {
      _resumeBinding(tester);
      auth.setSignedInDid('did:plc:alice');
      when(api.getUnreadCount()).thenAnswer((_) async => 5);
      final provider = UnreadNotificationCountProvider(
        apiService: api,
        authProvider: auth,
      );
      try {
        await tester.pump();
        expect(provider.count, 5);
        verify(api.getUnreadCount()).called(1);
        final observed = <int>[];
        provider.addListener(() => observed.add(provider.count));

        auth.setSignedInDid(null);
        expect(provider.count, 0);
        expect(observed, contains(0));
        await tester.pump(const Duration(seconds: 90));
        verifyNever(api.getUnreadCount());
      } finally {
        provider.dispose();
        _resumeBinding(tester);
      }
    });

    testWidgets('B4 DID switch clears the previous account count immediately', (
      tester,
    ) async {
      _resumeBinding(tester);
      auth.setSignedInDid('did:plc:alice');
      when(api.getUnreadCount()).thenAnswer((_) async => 5);
      final provider = UnreadNotificationCountProvider(
        apiService: api,
        authProvider: auth,
      );
      try {
        await tester.pump();
        expect(provider.count, 5);
        verify(api.getUnreadCount()).called(1);
        auth.setSignedInDid('did:plc:bob');
        expect(provider.count, 0);
        await tester.pump();
        verify(api.getUnreadCount()).called(1);
        await tester.pump(const Duration(seconds: 30));
        verify(api.getUnreadCount()).called(1);
        await tester.pump(const Duration(seconds: 30));
        verify(api.getUnreadCount()).called(1);
      } finally {
        provider.dispose();
        _resumeBinding(tester);
      }
    });

    for (final (name, action) in [
      ('switching to another DID', 'switch'),
      ('signing out', 'signOut'),
      ('signing out and back into the same DID', 'sameDid'),
    ]) {
      testWidgets('B4 late fetch is discarded after $name', (tester) async {
        _resumeBinding(tester);
        auth.setSignedInDid('did:plc:alice');
        final oldAnswer = Completer<int>();
        final newAnswer = Completer<int>();
        var calls = 0;
        when(
          api.getUnreadCount(),
        ).thenAnswer((_) => calls++ == 0 ? oldAnswer.future : newAnswer.future);
        final provider = UnreadNotificationCountProvider(
          apiService: api,
          authProvider: auth,
        );
        try {
          await tester.pump();
          verify(api.getUnreadCount()).called(1);
          if (action == 'switch') {
            auth.setSignedInDid('did:plc:bob');
          } else {
            auth.setSignedInDid(null);
            if (action == 'sameDid') {
              auth.setSignedInDid('did:plc:alice');
            }
          }
          if (action != 'signOut') {
            newAnswer.complete(2);
            await tester.pump();
            expect(provider.count, 2);
          } else {
            expect(provider.count, 0);
          }

          oldAnswer.complete(9);
          await tester.pump();
          expect(provider.count, action == 'signOut' ? 0 : 2);
        } finally {
          provider.dispose();
          _resumeBinding(tester);
        }
      });
    }

    for (final (name, error) in [
      ('ApiException', ApiException('Invalid response')),
      ('AuthenticationException', AuthenticationException('Expired')),
      ('ServerException', ServerException('Unavailable', statusCode: 500)),
      ('NetworkException', NetworkException('Offline')),
    ]) {
      testWidgets('B5 $name on refresh preserves the last count', (
        tester,
      ) async {
        _resumeBinding(tester);
        auth.setSignedInDid('did:plc:alice');
        var calls = 0;
        when(api.getUnreadCount()).thenAnswer((_) async {
          if (calls++ == 0) {
            return 3;
          }
          throw error;
        });
        final provider = UnreadNotificationCountProvider(
          apiService: api,
          authProvider: auth,
        );
        try {
          await tester.pump();
          expect(provider.count, 3);
          final observed = <int>[];
          provider.addListener(() => observed.add(provider.count));

          await provider.refresh();
          expect(provider.count, 3);
          expect(observed, everyElement(3));
          verify(api.getUnreadCount()).called(2);
        } finally {
          provider.dispose();
          _resumeBinding(tester);
        }
      });
    }
  });
}
