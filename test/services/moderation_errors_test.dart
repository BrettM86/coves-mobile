import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/services/moderation_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('U1 maps moderation errors to their recovery and user-visible copy', () {
    final cases =
        <
          ({
            Object exception,
            ModerationErrorCode code,
            ModerationRecovery recovery,
            String message,
          })
        >[
          (
            exception: ApiException(
              'conflict',
              statusCode: 400,
              errorCode: 'StateConflict',
            ),
            code: ModerationErrorCode.stateConflict,
            recovery: ModerationRecovery.reloadAndConfirm,
            message: 'Someone else acted on this first. Confirm again.',
          ),
          (
            exception: ApiException(
              'edited',
              statusCode: 400,
              errorCode: 'ContentChanged',
            ),
            code: ModerationErrorCode.contentChanged,
            recovery: ModerationRecovery.showNewVersion,
            message:
                'The author edited this post. '
                'Review the new version before acting.',
          ),
          (
            exception: ApiException(
              'conflict',
              statusCode: 400,
              errorCode: 'IdempotencyConflict',
            ),
            code: ModerationErrorCode.idempotencyConflict,
            recovery: ModerationRecovery.reloadAndConfirm,
            message: 'Something went wrong. Confirm again.',
          ),
          for (final (code, mapped) in [
            ('DecisionNotFound', ModerationErrorCode.decisionNotFound),
            ('InvalidDecision', ModerationErrorCode.invalidDecision),
            ('SubjectNotFound', ModerationErrorCode.subjectNotFound),
            ('InvalidSubject', ModerationErrorCode.invalidSubject),
          ])
            (
              exception: ApiException('gone', statusCode: 400, errorCode: code),
              code: mapped,
              recovery: ModerationRecovery.reloadSubject,
              message: 'This item changed. Showing the latest version.',
            ),
          (
            exception: ServerException(
              'down',
              statusCode: 503,
              errorCode: 'ModerationUnavailable',
            ),
            code: ModerationErrorCode.moderationUnavailable,
            recovery: ModerationRecovery.ambiguousRetry,
            message: 'Moderation is temporarily unavailable. Try again.',
          ),
          (
            exception: ApiException(
              'forbidden',
              statusCode: 403,
              errorCode: 'Forbidden',
            ),
            code: ModerationErrorCode.forbidden,
            recovery: ModerationRecovery.revokeAuthority,
            message: 'You no longer have admin access.',
          ),
          for (final (code, mapped) in [
            ('UnsupportedReason', ModerationErrorCode.unsupportedReason),
            ('UnsupportedLabel', ModerationErrorCode.unsupportedLabel),
            ('InvalidRequest', ModerationErrorCode.invalidRequest),
          ])
            (
              exception: ApiException(
                'invalid',
                statusCode: 400,
                errorCode: code,
              ),
              code: mapped,
              recovery: ModerationRecovery.clientBug,
              message: "Couldn't complete this action.",
            ),
          (
            exception: NetworkException('connection lost'),
            code: ModerationErrorCode.network,
            recovery: ModerationRecovery.ambiguousRetry,
            message: 'Moderation is temporarily unavailable. Try again.',
          ),
          (
            exception: ServerException('down', statusCode: 503),
            code: ModerationErrorCode.moderationUnavailable,
            recovery: ModerationRecovery.ambiguousRetry,
            message: 'Moderation is temporarily unavailable. Try again.',
          ),
          (
            exception: ServerException(
              'internal',
              statusCode: 500,
              errorCode: 'InternalServerError',
            ),
            code: ModerationErrorCode.moderationUnavailable,
            recovery: ModerationRecovery.ambiguousRetry,
            message: 'Moderation is temporarily unavailable. Try again.',
          ),
          (
            exception: FederationException('Failed host lookup'),
            code: ModerationErrorCode.network,
            recovery: ModerationRecovery.ambiguousRetry,
            message: 'Moderation is temporarily unavailable. Try again.',
          ),
          (
            exception: ApiException(
              'new code',
              statusCode: 400,
              errorCode: 'SomethingNew',
            ),
            code: ModerationErrorCode.unknown,
            recovery: ModerationRecovery.clientBug,
            message: "Couldn't complete this action.",
          ),
        ];

    for (final row in cases) {
      final mapped = ModerationError.fromException(row.exception);
      expect(mapped.code, row.code, reason: '${row.exception}');
      expect(mapped.recovery, row.recovery, reason: '${row.exception}');
      expect(mapped.message, row.message, reason: '${row.exception}');
    }
  });
}
