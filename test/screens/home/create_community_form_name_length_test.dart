// Acceptance test for the community-name length budget, observed through
// the create form rather than the validator.
//
// The backend mints the handle `c-<name>.coves.social`, so the handle's
// first label is `c-` plus the name. The PDS caps that label at 18
// characters, which leaves 16 for the name. The literals 16/17/18 are
// deliberate: deriving them from CommunityNameValidator.maxLength would let
// a wrong constant pass its own regression test.

import 'package:coves_flutter/models/community.dart';
import 'package:coves_flutter/screens/home/create_community_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/theme_pump.dart';

void main() {
  testWidgets('a 17-character name is rejected with the 16 limit, and a '
      '16-character name is submitted with an 18-character handle label', (
    tester,
  ) async {
    final nameController = TextEditingController();
    final displayNameController = TextEditingController();
    final descriptionController = TextEditingController();
    addTearDown(nameController.dispose);
    addTearDown(displayNameController.dispose);
    addTearDown(descriptionController.dispose);

    var submitCount = 0;

    await pumpUnderAppTheme(
      tester,
      CreateCommunityForm(
        nameController: nameController,
        displayNameController: displayNameController,
        descriptionController: descriptionController,
        createdCommunities: const <CreateCommunityResponse>[],
        isSubmitting: false,
        onSubmit: () => submitCount++,
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    final nameField = fields.at(0);
    final displayNameField = fields.at(1);
    final descriptionField = fields.at(2);

    // The heading also reads "Create Community"; the button is the one
    // inside an ElevatedButton.
    final createButton = find.widgetWithText(
      ElevatedButton,
      'Create Community',
    );

    Future<void> tapCreate() async {
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await tester.pumpAndSettle();
    }

    await tester.enterText(displayNameField, 'World News');
    await tester.enterText(descriptionField, 'Global news');

    // Given a 17-character name.
    await tester.enterText(nameField, 'a' * 17);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(createButton).onPressed,
      isNotNull,
      reason: 'all three fields are filled, so Create must be enabled',
    );

    // When Create is tapped.
    await tapCreate();

    // Then nothing is submitted and the name field names the 16 limit.
    expect(
      submitCount,
      0,
      reason:
          'c- plus a 17-character name is a 19-character handle label, '
          'which exceeds the PDS cap of 18',
    );
    expect(
      find.descendant(of: nameField, matching: find.textContaining('16')),
      findsOneWidget,
      reason: 'the rendered name error must state 16 as the limit',
    );

    // Given a 16-character name.
    await tester.enterText(nameField, 'a' * 16);
    await tester.pumpAndSettle();

    // When Create is tapped.
    await tapCreate();

    // Then it is submitted exactly once.
    expect(submitCount, 1);

    // And the previewed handle's first label is exactly the PDS cap of 18.
    final handlePreview = find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data?.startsWith('@') ?? false),
    );
    expect(handlePreview, findsOneWidget);
    final handle = tester.widget<Text>(handlePreview).data!;
    final firstLabel = handle.substring(1).split('.').first;
    expect(firstLabel, 'c-${'a' * 16}');
  });
}
