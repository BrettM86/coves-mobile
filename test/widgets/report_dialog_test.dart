import 'package:coves_flutter/services/coves_api_service.dart';
import 'package:coves_flutter/widgets/report_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test_helpers/error_copy_rows.dart';
import '../test_helpers/pump_helpers.dart';
import '../test_helpers/test_mocks.dart';
import '../test_helpers/theme_pump.dart';

void main() {
  group('ReportDialog submit failure copy', () {
    for (final row in errorCopyRows(
      'Could not submit report. Please try again.',
    )) {
      testWidgets('a ${row.name} failure shows "${row.expected}"', (
        tester,
      ) async {
        final apiService = MockCovesApiService();
        when(
          apiService.submitReport(
            targetUri: anyNamed('targetUri'),
            reason: anyNamed('reason'),
            explanation: anyNamed('explanation'),
          ),
        ).thenThrow(row.error);
        // The submit awaits HapticFeedback, which never completes without a
        // platform handler.
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (methodCall) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await pumpUnderAppTheme(
          tester,
          Provider<CovesApiService>.value(
            value: apiService,
            child: const ReportDialog(
              targetUri: 'at://did:plc:author/social.coves.post/1',
              contentType: 'post',
            ),
          ),
        );
        await tester.tap(find.text('Spam'));
        await tester.pump();
        await tester.tap(find.text('Submit Report'));
        await pumpFrames(tester);

        expect(
          find.descendant(
            of: find.byType(ReportDialog),
            matching: find.text(row.expected),
          ),
          findsOneWidget,
        );
        if (row.rawText case final rawText?) {
          expect(find.textContaining(rawText), findsNothing);
        }
      });
    }
  });
}
