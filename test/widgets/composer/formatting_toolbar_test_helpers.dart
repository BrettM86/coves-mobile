import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:coves_flutter/widgets/composer/formatting_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A toolbar test with semantics enabled for its whole body.
void toolbarTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      semantics.dispose();
    }
  });
}

/// The toolbar button labelled exactly [label] ('Code' never matches
/// 'Code block').
Finder button(String label) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$'));

/// Pumps a [FormattingToolbar] over [controller], below a [FacetTextField]
/// bound to the same controller when [withField], inside a box [width] wide
/// when given.
Future<void> pumpToolbar(
  WidgetTester tester,
  FacetEditingController controller, {
  List<Widget> leading = const [],
  List<Widget> trailing = const [],
  bool withField = false,
  double? width,
}) async {
  addTearDown(controller.dispose);
  Widget body = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (withField) FacetTextField(controller: controller, maxLines: 4),
      FormattingToolbar(
        controller: controller,
        leading: leading,
        trailing: trailing,
      ),
    ],
  );
  if (width != null) {
    body = Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: body),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: body),
    ),
  );
}

/// Focuses the field, the only [EditableText] unless [field] names one, and
/// gives it [selection] as a user tap would.
Future<void> focusField(
  WidgetTester tester,
  TextSelection selection, {
  Finder? field,
}) async {
  final editable = field ?? find.byType(EditableText);
  await tester.showKeyboard(editable);
  await tester.pump();
  final state = tester.state<EditableTextState>(editable);
  state.userUpdateTextEditingValue(
    state.textEditingValue.copyWith(selection: selection),
    SelectionChangedCause.tap,
  );
  await tester.pump();
}

/// Types through the platform text input: the field's text becomes [text]
/// with the caret at [caret].
Future<void> typeAs(WidgetTester tester, String text, int caret) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    ),
  );
  await tester.pump();
}

/// Taps the toolbar button labelled [label].
Future<void> tapButton(WidgetTester tester, String label) async {
  expect(button(label), findsOneWidget, reason: 'toolbar button "$label"');
  await tester.tap(button(label));
  await tester.pump();
}

/// The selected state the button labelled [label] exposes.
Tristate selectedState(WidgetTester tester, String label) {
  expect(button(label), findsOneWidget, reason: 'toolbar button "$label"');
  return tester.getSemantics(button(label)).flagsCollection.isSelected;
}

/// A controller over [text] with the selection [start]..[end].
FacetEditingController selected(String text, int start, int end) =>
    FacetEditingController(text: text)
      ..selection = TextSelection(baseOffset: start, extentOffset: end);

/// The heading picker's entries' semantic labels.
const pickerLabels = ['Heading 1', 'Heading 2', 'Heading 3', 'Normal text'];

/// The enabled state the button labelled [label] exposes.
Tristate enabledState(WidgetTester tester, String label) {
  expect(button(label), findsOneWidget, reason: 'button "$label"');
  return tester.getSemantics(button(label)).flagsCollection.isEnabled;
}

/// Taps the Heading button and lets the picker open.
Future<void> openPicker(
  WidgetTester tester, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  expect(button('Heading'), findsOneWidget, reason: 'toolbar button "Heading"');
  await tester.tap(button('Heading'), kind: kind);
  await tester.pumpAndSettle();
}

/// Taps the picker entry labelled [entry] and lets the picker close.
Future<void> pickEntry(
  WidgetTester tester,
  String entry, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  expect(button(entry), findsOneWidget, reason: 'picker entry "$entry"');
  await tester.tap(button(entry), kind: kind);
  await tester.pumpAndSettle();
}
