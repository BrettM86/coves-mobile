import 'package:coves_flutter/constants/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] under the real application theme.
///
/// Most widget tests in this suite pump a bare `MaterialApp`, which silently
/// applies Material's *default light* theme - so nothing they render can
/// observe the app's actual colors or typography. Use this helper whenever a
/// test needs to assert against themed values.
///
/// Must be awaited from inside `testWidgets`: the theme pulls fonts through
/// `google_fonts`, whose loader only stays inert inside the fake-async zone
/// that `testWidgets` installs.
Future<void> pumpUnderAppTheme(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child)),
  );
}
