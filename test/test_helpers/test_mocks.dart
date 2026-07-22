// Shared mockito mocks for widget tests.
//
// Widget tests previously imported generated mocks from
// test/providers/comments_provider_test.mocks.dart, coupling them to another
// test file's codegen. This helper owns the @GenerateMocks annotation for the
// interfaces shared across widget tests; import `test_mocks.mocks.dart`
// (re-exported here) instead of reaching into test/providers.
//
// Regenerate with:
//   dart run build_runner build --delete-conflicting-outputs

import 'package:coves_flutter/providers/auth_provider.dart';
import 'package:coves_flutter/providers/vote_provider.dart';
import 'package:coves_flutter/services/comment_service.dart';
import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:mockito/annotations.dart';

export 'test_mocks.mocks.dart';

@GenerateMocks([AuthProvider, CovesApiService, VoteProvider, CommentService])
// ignore: unreachable_from_main
void main() {}
