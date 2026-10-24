import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/utils/error_messages.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ApiException mapResponse(int statusCode, Object? data) {
    final requestOptions = RequestOptions(path: '/xrpc/x');
    return ApiException.fromDioError(
      DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: statusCode,
          data: data,
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }

  group(
    'getErrorMessage shows the server message for plain 4xx ApiExceptions',
    () {
      final humanMessageCases = <({int statusCode, String message})>[
        (statusCode: 400, message: 'Post title is required'),
        (statusCode: 403, message: 'You can only delete your own comments'),
        (
          statusCode: 409,
          message: 'You are already subscribed to this community',
        ),
        (statusCode: 429, message: 'Too many votes. Slow down.'),
        (statusCode: 499, message: 'Client closed the request'),
      ];

      for (final testCase in humanMessageCases) {
        test('status ${testCase.statusCode} returns "${testCase.message}"', () {
          final error = ApiException(
            testCase.message,
            statusCode: testCase.statusCode,
          );

          expect(error.errorCode, isNull);
          expect(
            getErrorMessage(error, fallback: 'Fallback copy.'),
            testCase.message,
          );
        });
      }

      test('ErrorMessage.comment of a mapped 403 Banned body returns its '
          'human message', () {
        final error = mapResponse(403, <String, dynamic>{
          'error': 'Banned',
          'message': 'User is banned from this community',
        });

        expect(
          ErrorMessage.comment(error),
          'User is banned from this community',
        );
      });

      test('ErrorMessage.vote of a mapped 429 plain-text body returns it '
          'trimmed', () {
        final error = mapResponse(
          429,
          'Rate limit exceeded. Please try again later.\n',
        );

        expect(
          ErrorMessage.vote(error),
          'Rate limit exceeded. Please try again later.',
        );
      });
    },
  );

  group('getErrorMessage existing behavior guards (pass before and after the '
      'fix)', () {
    test('plain ApiException with status 399 returns the fallback', () {
      final error = ApiException('Odd status message', statusCode: 399);

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('plain ApiException with status 500 returns the fallback', () {
      final error = ApiException('Unexpected error: boom', statusCode: 500);

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('plain ApiException without a status returns the fallback', () {
      final error = ApiException('CommentService not available');

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('plain 403 ApiException with an empty message returns the '
        'fallback', () {
      final error = ApiException('', statusCode: 403);

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('plain 403 ApiException with a whitespace-only message returns the '
        'fallback', () {
      final error = ApiException('   ', statusCode: 403);

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('plain ApiException constructed with status 401 returns the '
        'fallback', () {
      final error = ApiException('Token expired', statusCode: 401);

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('plain ApiException constructed with status 404 returns the '
        'fallback', () {
      final error = ApiException('Record not found', statusCode: 404);

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('AuthenticationException keeps its sign-in copy', () {
      final error = AuthenticationException('Token expired');

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Please sign in to continue.',
      );
    });

    test('NotFoundException keeps its not-found copy', () {
      final error = NotFoundException('Post not found');

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Content not found. It may have been removed.',
      );
    });

    test('ServerException from a mapped 500 JSON body keeps its server '
        'copy', () {
      final error = mapResponse(500, <String, dynamic>{
        'error': 'InternalError',
        'message': 'database connection lost',
      });

      expect(error, isA<ServerException>());
      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Server error. Please try again later.',
      );
    });

    test('NetworkException keeps its connection copy', () {
      final error = NetworkException('Connection refused');

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'No connection. Please check your internet.',
      );
    });

    test('FederationException keeps its federation copy', () {
      final error = FederationException('DNS lookup failed');

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Could not reach the server. Please try again.',
      );
    });

    test('ValidationException returns its own message', () {
      final error = ValidationException('Name too long');

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Name too long',
      );
    });

    test('a non-API error returns the given fallback', () {
      expect(
        getErrorMessage(StateError('x'), fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('a non-API error without a fallback returns the default copy', () {
      expect(
        getErrorMessage(StateError('x')),
        'Something went wrong. Please try again.',
      );
    });

    test('ErrorMessage.vote of a plain ApiException without a status returns '
        'the vote fallback', () {
      final error = ApiException('VoteService not available');

      expect(
        ErrorMessage.vote(error),
        'Could not update your vote. Please try again.',
      );
    });
  });

  group('getErrorMessage hides a machine error code standing in for the '
      'message', () {
    test('ErrorMessage.vote of a mapped 429 code-only body returns the vote '
        'fallback', () {
      final error = mapResponse(429, <String, dynamic>{
        'error': 'RateLimitExceeded',
      });

      expect(error.message, 'RateLimitExceeded');
      expect(error.errorCode, 'RateLimitExceeded');
      expect(
        ErrorMessage.vote(error),
        'Could not update your vote. Please try again.',
      );
    });

    test('plain 403 ApiException whose message equals its error code returns '
        'the fallback', () {
      final error = ApiException(
        'Banned',
        statusCode: 403,
        errorCode: 'Banned',
      );

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });

    test('plain 403 ApiException with a human message beside its error code '
        'returns the human message', () {
      final error = ApiException(
        'User is banned from this community',
        statusCode: 403,
        errorCode: 'Banned',
      );

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'User is banned from this community',
      );
    });
  });

  group('getErrorMessage hides the synthetic diagnostic for an empty 4xx '
      'body', () {
    final emptyBodyCases = <({String description, Object? data})>[
      (description: 'a null body', data: null),
      (description: 'an empty String body', data: ''),
      (description: 'an empty JSON map body', data: <String, dynamic>{}),
    ];

    for (final testCase in emptyBodyCases) {
      test('ErrorMessage.comment of a mapped 413 with '
          '${testCase.description} returns the comment fallback', () {
        final error = mapResponse(413, testCase.data);

        expect(error.message, 'Request failed with status 413');
        expect(error.errorCode, isNull);
        expect(
          ErrorMessage.comment(error),
          'Could not post comment. Please try again.',
        );
      });
    }
  });

  group('getErrorMessage hides a 4xx body that is not a short one-line '
      'message', () {
    final unsuitableBodyCases = <({String description, String data})>[
      (
        description: 'an HTML error page',
        data: '<html><body><h1>403 Forbidden</h1></body></html>',
      ),
      (description: 'a 5,000-character single-line body', data: 'a' * 5000),
      (
        description: 'a multi-line body split by a line feed',
        data: 'Request blocked.\nReference: 12345',
      ),
      (
        description: 'a multi-line body split by a carriage return',
        data: 'Request blocked.\rReference: 12345',
      ),
    ];

    for (final testCase in unsuitableBodyCases) {
      test('ErrorMessage.comment of a mapped 403 with '
          '${testCase.description} returns the comment fallback', () {
        final error = mapResponse(403, testCase.data);

        expect(error.message, testCase.data);
        expect(
          ErrorMessage.comment(error),
          'Could not post comment. Please try again.',
        );
      });
    }

    test('a mapped 403 body of exactly 200 characters is shown', () {
      final body = 'a' * 200;
      final error = mapResponse(403, body);

      expect(getErrorMessage(error, fallback: 'Fallback copy.'), body);
    });

    test('a mapped 403 body of 201 characters returns the fallback', () {
      final error = mapResponse(403, 'a' * 201);

      expect(
        getErrorMessage(error, fallback: 'Fallback copy.'),
        'Fallback copy.',
      );
    });
  });

  group('ErrorMessage operation fallbacks', () {
    const cases = <(String, String Function(Object), String)>[
      (
        'updateProfile',
        ErrorMessage.updateProfile,
        'Could not update profile. Please try again.',
      ),
      (
        'loadCommunities',
        ErrorMessage.loadCommunities,
        'Could not load communities. Please try again.',
      ),
      (
        'createCommunity',
        ErrorMessage.createCommunity,
        'Could not create community. Please try again.',
      ),
      (
        'uploadAvatar',
        ErrorMessage.uploadAvatar,
        'Could not upload avatar. Please try again.',
      ),
      (
        'deleteComment',
        ErrorMessage.deleteComment,
        'Could not delete comment. Please try again.',
      ),
      (
        'loadReplies',
        ErrorMessage.loadReplies,
        'Could not load replies. Please try again.',
      ),
      (
        'loadProfilePosts',
        ErrorMessage.loadProfilePosts,
        'Could not load posts. Please try again.',
      ),
      (
        'loadProfileComments',
        ErrorMessage.loadProfileComments,
        'Could not load comments. Please try again.',
      ),
    ];

    for (final (name, helper, expected) in cases) {
      test('ErrorMessage.$name of a 500 wrapper returns its fallback', () {
        final error = ApiException(
          'Unexpected error: FormatException: x',
          statusCode: 500,
        );

        expect(helper(error), expected);
      });
    }
  });

  group('profile helpers name a missing actor', () {
    // The AppView answers ActorNotFound (404) for an account that never
    // existed, so "It may have been removed" copy would be wrong.
    const cases = <(String, String Function(Object))>[
      ('profile', ErrorMessage.profile),
      ('loadProfilePosts', ErrorMessage.loadProfilePosts),
      ('loadProfileComments', ErrorMessage.loadProfileComments),
    ];

    for (final (name, helper) in cases) {
      test('ErrorMessage.$name of a NotFoundException returns "User not '
          'found."', () {
        expect(helper(NotFoundException('ActorNotFound')), 'User not found.');
      });
    }
  });

  group('ErrorMessage.notificationPreferences', () {
    test('NetworkException returns the connection copy', () {
      expect(
        ErrorMessage.notificationPreferences(
          NetworkException('Connection refused'),
        ),
        'No connection. Please check your internet.',
      );
    });

    test('AuthenticationException returns the sign-in copy', () {
      expect(
        ErrorMessage.notificationPreferences(
          AuthenticationException('Token expired'),
        ),
        'Please sign in to continue.',
      );
    });

    test('a plain 400 ApiException returns the server message', () {
      expect(
        ErrorMessage.notificationPreferences(
          ApiException('Preferences payload is invalid', statusCode: 400),
        ),
        'Preferences payload is invalid',
      );
    });

    test('a plain ApiException without a status returns the update '
        'fallback', () {
      expect(
        ErrorMessage.notificationPreferences(ApiException('Unexpected')),
        "Couldn't update notification settings. Try again.",
      );
    });

    test('a non-API error returns the update fallback', () {
      expect(
        ErrorMessage.notificationPreferences(StateError('x')),
        "Couldn't update notification settings. Try again.",
      );
    });

    test('a non-API error while loading returns the load fallback', () {
      expect(
        ErrorMessage.notificationPreferences(StateError('x'), isLoad: true),
        "Couldn't load notification settings. Try again.",
      );
    });
  });
}
