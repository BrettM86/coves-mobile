import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/models/user_profile.dart';
import 'package:coves_flutter/screens/home/edit_profile_screen.dart';
import 'package:coves_flutter/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/default_avatar_expectations.dart';

/// The edit screen shows the user's DID default when they have no avatar, as
/// their profile header does, instead of a person icon.
void main() {
  testWidgets('a profile with no avatar shows its DID default, not the '
      'person icon', (tester) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: EditProfileScreen(
          profile: UserProfile(
            did: 'did:plc:z72i7hdynmk6r22z27h6tvur',
            handle: 'someone.example.com',
          ),
        ),
      ),
    );
    await tester.pump();

    expectDefaultAvatar(
      find.byType(UserAvatar),
      url: 'http://127.0.0.1:1/img/default-avatars/v1/pufferfish.webp',
      tint: 0xFFD8E8D4,
    );
    expect(find.byIcon(Icons.person), findsNothing);
  });
}
