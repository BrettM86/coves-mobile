import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/constants/image_upload_limits.dart';
import 'package:coves_flutter/models/picked_image.dart';
import 'package:coves_flutter/models/upload_image_response.dart';
import 'package:coves_flutter/providers/image_attachments_controller.dart';
import 'package:coves_flutter/utils/alt_text_limits.dart';
import 'package:coves_flutter/widgets/composer/image_attachment_strip.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/image_fixtures.dart';
import '../../test_helpers/image_strip_helpers.dart';
import '../../test_helpers/pump_helpers.dart';

const _pathA = '/picked/a.png';
const _pathB = '/picked/b.png';
const _pathC = '/picked/c.png';

/// The strip never uploads in these tests.
Future<UploadImageResponse> _noUpload(
  Uint8List bytes,
  String contentType, {
  ProgressCallback? onSendProgress,
}) => throw StateError('no upload expected');

PickedImage _picked(String path, int size) => PickedImage(
  file: File(path),
  bytes: headerBytes(png(size, size)),
  mimeType: 'image/png',
);

Finder _tile(int index) => find.byKey(Key('image-attachment-tile-$index'));
Finder _altControl(int index) => find.byKey(Key('image-attachment-alt-$index'));
Finder _altSet(int index) => find.byKey(Key('image-attachment-alt-set-$index'));
final _editorField = find.byKey(const Key('image-alt-editor-field'));
final _editorSave = find.byKey(const Key('image-alt-editor-save'));
final _editorCounter = find.byKey(const Key('image-alt-editor-counter'));

/// The file each tile draws, in tile order.
List<String> _tilePaths(WidgetTester tester) => [
  for (var index = 0; index < 3; index++) ...imagePathsIn(tester, _tile(index)),
];

/// The text in the alt editor's field.
String _editorText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: _editorField,
        matching: find.byType(EditableText),
        matchRoot: true,
      ),
    )
    .controller
    .text;

void main() {
  /// Pumps the strip with attachments a, b and c on a surface wide enough
  /// for the three tiles and the Add tile; returns its controller.
  Future<ImageAttachmentsController> pumpStrip(
    WidgetTester tester, {
    bool enabled = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = ImageAttachmentsController(upload: _noUpload);
    addTearDown(controller.dispose);
    expect(
      controller.add([
        _picked(_pathA, 11),
        _picked(_pathB, 12),
        _picked(_pathC, 13),
      ]),
      isNull,
    );

    // A fresh app per call, so rows share no routes or element state.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ImageAttachmentStrip(
            controller: controller,
            onAdd: () {},
            enabled: enabled,
          ),
        ),
      ),
    );
    await pumpFrames(tester);
    expect(_tilePaths(tester), [_pathA, _pathB, _pathC]);
    return controller;
  }

  /// Opens tile [index]'s alt editor.
  Future<void> openEditor(WidgetTester tester, int index) async {
    expect(_altControl(index), findsOneWidget, reason: 'Alt control $index');
    await tester.tap(_altControl(index));
    await pumpFrames(tester);
  }

  Future<void> saveAlt(WidgetTester tester, int index, String alt) async {
    await openEditor(tester, index);
    await tester.enterText(_editorField, alt);
    await tester.pump();
    await tester.tap(_editorSave);
    await pumpFrames(tester);
  }

  group('drag reorder', () {
    testWidgets('a long-press drag moves the tile and its attachment; a drag '
        'without the hold, or while disabled, does not', (tester) async {
      final rows = [
        (
          name: 'tile 0 to the end',
          from: 0,
          to: 2,
          hold: true,
          enabled: true,
          expected: [_pathB, _pathC, _pathA],
        ),
        (
          name: 'tile 2 to the front',
          from: 2,
          to: 0,
          hold: true,
          enabled: true,
          expected: [_pathC, _pathA, _pathB],
        ),
        (
          name: 'no long-press hold',
          from: 0,
          to: 2,
          hold: false,
          enabled: true,
          expected: [_pathA, _pathB, _pathC],
        ),
        (
          name: 'disabled',
          from: 0,
          to: 2,
          hold: true,
          enabled: false,
          expected: [_pathA, _pathB, _pathC],
        ),
      ];
      for (final row in rows) {
        final controller = await pumpStrip(tester, enabled: row.enabled);
        await longPressDrag(
          tester,
          _tile(row.from),
          _tile(row.to),
          holdForLongPress: row.hold,
        );
        expect(
          controller.attachments.map((a) => a.file.path).toList(),
          row.expected,
          reason: '${row.name}: controller order',
        );
        expect(
          _tilePaths(tester),
          row.expected,
          reason: '${row.name}: rendered order',
        );
      }
    });

    testWidgets('a screen reader "Move right" moves the tile while enabled and '
        'does nothing while disabled', (tester) async {
      final semantics = tester.ensureSemantics();
      const moveRight = CustomSemanticsAction(label: 'Move right');
      final rows = [
        (enabled: true, expected: [_pathB, _pathA, _pathC]),
        (enabled: false, expected: [_pathA, _pathB, _pathC]),
      ];
      for (final row in rows) {
        final controller = await pumpStrip(tester, enabled: row.enabled);
        final moveRightId = CustomSemanticsAction.getIdentifier(moveRight);
        final tile = find.semantics.ancestor(
          of: find.semantics.byLabel('Image 1 of 3'),
          matching: find.semantics.byPredicate(
            (node) => node
                .getSemanticsData()
                .customSemanticsActionIds!
                .contains(moveRightId),
          ),
        );
        tester.semantics.performAction(
          tile.first,
          SemanticsAction.customAction,
          args: moveRightId,
        );
        await pumpFrames(tester);
        expect(
          controller.attachments.map((a) => a.file.path).toList(),
          row.expected,
          reason: 'enabled: ${row.enabled}',
        );
      }
      semantics.dispose();
    });
  });

  group('alt editor', () {
    testWidgets('saving "a cat" on tile 0 stores it and marks only tile 0 as '
        'having alt text, visibly and in its semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = await pumpStrip(tester);

      await saveAlt(tester, 0, 'a cat');

      expect(_editorField, findsNothing, reason: 'Save closes the editor');
      expect(controller.attachments.map((a) => a.alt).toList(), [
        'a cat',
        '',
        '',
      ]);
      expect(_altSet(0), findsOneWidget);
      expect(_altSet(1), findsNothing);
      expect(
        find.descendant(
          of: _tile(0),
          matching: find.bySemanticsLabel(RegExp('Alt text set')),
          matchRoot: true,
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: _tile(1),
          matching: find.bySemanticsLabel(RegExp('Alt text set')),
          matchRoot: true,
        ),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets('reopening shows the saved alt; dismissing an edit without '
        'Save keeps the saved alt', (tester) async {
      final controller = await pumpStrip(tester);
      await saveAlt(tester, 0, 'a cat');

      await openEditor(tester, 0);
      expect(_editorText(tester), 'a cat');
      await tester.enterText(_editorField, 'dog');
      await tester.pump();
      // The modal barrier above the sheet.
      await tester.tapAt(const Offset(20, 20));
      await pumpFrames(tester);

      expect(_editorField, findsNothing, reason: 'the editor was dismissed');
      expect(controller.attachments.first.alt, 'a cat');
      expect(_altSet(0), findsOneWidget);
    });

    testWidgets('in a short landscape viewport with the keyboard up, eight '
        'lines of alt text still leave Save reachable', (tester) async {
      final controller = await pumpStrip(tester);
      tester.view.physicalSize = const Size(844, 390);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await pumpFrames(tester);

      await openEditor(tester, 0);
      final alt = List.generate(8, (line) => 'line $line').join('\n');
      await tester.enterText(_editorField, alt);
      await tester.pump();
      await tester.ensureVisible(_editorSave);
      await tester.pump();
      await tester.tap(_editorSave);
      await pumpFrames(tester);

      expect(controller.attachments.first.alt, alt);
    });

    testWidgets('saving only spaces shows no alt-set mark; while disabled the '
        'Alt control opens no editor', (tester) async {
      final semantics = tester.ensureSemantics();
      bool altHasTap() => find.semantics
          .byLabel('Alt text for image 1')
          .evaluate()
          .single
          .getSemanticsData()
          .hasAction(SemanticsAction.tap);

      await pumpStrip(tester);
      expect(altHasTap(), isTrue, reason: 'enabled Alt control semantics');
      await saveAlt(tester, 0, '   ');
      expect(_altSet(0), findsNothing, reason: 'blank alt');

      await pumpStrip(tester, enabled: false);
      expect(altHasTap(), isFalse, reason: 'disabled Alt control semantics');
      await tester.tap(_altControl(0), warnIfMissed: false);
      await pumpFrames(tester);
      expect(_editorField, findsNothing, reason: 'disabled strip');
      semantics.dispose();
    });
  });

  group('alt editor limits', () {
    const family = '👨‍👩‍👧‍👦';

    testWidgets('an edit past either limit keeps the old text; the counter '
        'shows what remains near the limit and is absent far from it', (
      tester,
    ) async {
      final rows = [
        (
          name: '1000 graphemes, then 1001',
          accepted: 'a' * 1000,
          refused: 'a' * 1001,
          counter: '0',
        ),
        (
          name: '10,000 bytes, then one more grapheme',
          accepted: family * 400,
          refused: '${family * 400}a',
          counter: '0',
        ),
        (
          name: '10 graphemes',
          accepted: 'a' * 10,
          refused: null,
          counter: null,
        ),
      ];
      for (final row in rows) {
        await pumpStrip(tester);
        await openEditor(tester, 0);
        await tester.enterText(_editorField, row.accepted);
        await tester.pump();
        expect(_editorText(tester), row.accepted, reason: row.name);
        if (row.refused case final refused?) {
          await tester.enterText(_editorField, refused);
          await tester.pump();
          expect(_editorText(tester), row.accepted, reason: row.name);
        }
        if (row.counter case final counter?) {
          expect(
            find.descendant(
              of: _editorCounter,
              matching: find.text(counter),
              matchRoot: true,
            ),
            findsOneWidget,
            reason: '${row.name}: counter',
          );
        } else {
          expect(_editorCounter, findsNothing, reason: '${row.name}: counter');
        }
      }
    });

    testWidgets('pasting past the limit into an empty field keeps the text up '
        'to the limit, the caret at its end, and shows the counter at 0', (
      tester,
    ) async {
      await pumpStrip(tester);
      await openEditor(tester, 0);

      await tester.enterText(_editorField, 'a' * 1001);
      await tester.pump();

      expect(_editorText(tester), 'a' * 1000);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .selection,
        const TextSelection.collapsed(offset: 1000),
      );
      expect(
        find.descendant(
          of: _editorCounter,
          matching: find.text('0'),
          matchRoot: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a composition past the limit is accepted while composing and '
        'clipped when it commits; Save mid-composition stores clipped text', (
      tester,
    ) async {
      final controller = await pumpStrip(tester);
      await openEditor(tester, 0);
      await tester.enterText(_editorField, 'a' * 999);
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${'a' * 999}bcd',
          selection: const TextSelection.collapsed(offset: 1002),
          composing: const TextRange(start: 999, end: 1002),
        ),
      );
      await tester.pump();
      expect(_editorText(tester), '${'a' * 999}bcd', reason: 'composing');

      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${'a' * 999}bcd',
          selection: const TextSelection.collapsed(offset: 1002),
        ),
      );
      await tester.pump();
      expect(_editorText(tester), '${'a' * 999}b', reason: 'committed');

      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${'a' * 998}xyz',
          selection: const TextSelection.collapsed(offset: 1001),
          composing: const TextRange(start: 998, end: 1001),
        ),
      );
      await tester.pump();
      await tester.tap(_editorSave);
      await pumpFrames(tester);
      expect(controller.attachments.first.alt, '${'a' * 998}xy');
    });

    testWidgets('a clipped edit keeps the text around the edit position and '
        'puts the caret after the kept run', (tester) async {
      final tail = '${'a' * 497}Z';
      final rows = [
        (
          name: 'composition committed mid-text at the grapheme limit',
          before: TextEditingValue(
            text: '${'a' * 500}$tail',
            selection: const TextSelection.collapsed(offset: 500),
          ),
          edit: TextEditingValue(
            text: '${'a' * 500}bcd$tail',
            selection: const TextSelection.collapsed(offset: 503),
            composing: const TextRange(start: 500, end: 503),
          ),
          commit: true,
          text: '${'a' * 500}bc$tail',
          caret: 502,
        ),
        (
          name: 'paste whose start matches the following text',
          before: TextEditingValue(
            text: '${'a' * 998}Z',
            selection: const TextSelection.collapsed(offset: 0),
          ),
          edit: TextEditingValue(
            text: 'ab${'a' * 998}Z',
            selection: const TextSelection.collapsed(offset: 2),
          ),
          commit: false,
          text: '${'a' * 999}Z',
          caret: 1,
        ),
        (
          name: 'selection replaced past the grapheme limit',
          before: TextEditingValue(
            text: '${'a' * 500}XY$tail',
            selection: const TextSelection(baseOffset: 500, extentOffset: 502),
          ),
          edit: TextEditingValue(
            text: '${'a' * 500}aab$tail',
            selection: const TextSelection.collapsed(offset: 503),
          ),
          commit: false,
          text: '${'a' * 500}aa$tail',
          caret: 502,
        ),
      ];
      for (final row in rows) {
        await pumpStrip(tester);
        await openEditor(tester, 0);
        tester.testTextInput.updateEditingValue(row.before);
        await tester.pump();
        expect(_editorText(tester), row.before.text, reason: row.name);
        tester.testTextInput.updateEditingValue(row.edit);
        await tester.pump();
        if (row.commit) {
          tester.testTextInput.updateEditingValue(
            row.edit.copyWith(composing: TextRange.empty),
          );
          await tester.pump();
        }
        final value = tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .value;
        expect(value.text, row.text, reason: row.name);
        expect(
          value.selection,
          TextSelection.collapsed(offset: row.caret),
          reason: '${row.name}: caret',
        );
      }
    });

    testWidgets('an edit after an over-limit composition never drops text '
        'that was already there', (tester) async {
      // A composition is accepted as is, so the field can sit over the limit
      // when an unrelated edit arrives. The edit's new text is what stops;
      // a still-known composition is clipped to fit.
      final over = 'H${'a' * 997}bcdZ'; // 1002 graphemes, composing "bcd".
      final rows = [
        (
          name: '(a) disjoint insert while the composition is still marked',
          before: TextEditingValue(
            text: over,
            selection: const TextSelection.collapsed(offset: 1001),
            composing: const TextRange(start: 998, end: 1001),
          ),
          edit: TextEditingValue(
            text: 'XY$over',
            selection: const TextSelection.collapsed(offset: 2),
          ),
          text: 'H${'a' * 997}bZ',
          caret: 0,
        ),
        (
          name: '(c) repeated characters with a stale selection',
          before: TextEditingValue(
            text: '${'a' * 1001}Z',
            selection: const TextSelection.collapsed(offset: 1001),
            composing: const TextRange(start: 0, end: 3),
          ),
          edit: TextEditingValue(
            text: '${'a' * 1002}Z',
            selection: const TextSelection.collapsed(offset: 1002),
          ),
          // The selection outside the composition clears it, so nothing
          // is known to clip: the insert is dropped and the text kept.
          text: '${'a' * 1001}Z',
          caret: 1001,
        ),
      ];
      for (final row in rows) {
        await pumpStrip(tester);
        await openEditor(tester, 0);
        tester.testTextInput.updateEditingValue(row.before);
        await tester.pump();
        expect(_editorText(tester), row.before.text, reason: row.name);
        tester.testTextInput.updateEditingValue(row.edit);
        await tester.pump();
        final value = tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .value;
        expect(value.text, row.text, reason: row.name);
        expect(
          value.selection,
          TextSelection.collapsed(offset: row.caret),
          reason: '${row.name}: caret',
        );
      }
    });

    testWidgets('(b) a keystroke after the composition was cleared outside '
        'the formatter is dropped, not the end of the text', (tester) async {
      final strip = await pumpStrip(tester);
      await openEditor(tester, 0);
      final over = '${'a' * 999}bcZ';
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: over,
          selection: const TextSelection.collapsed(offset: 1001),
          composing: const TextRange(start: 999, end: 1001),
        ),
      );
      await tester.pump();
      // Moving the selection out of the composition clears it without a
      // formatter call, as a tap elsewhere in the field does.
      final controller =
          tester.widget<EditableText>(find.byType(EditableText)).controller
            ..selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(controller.value.composing, TextRange.empty);

      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: 'X$over',
          selection: const TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      expect(controller.text, over);

      // Deleting is always allowed, even while still over.
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: over.substring(1),
          selection: const TextSelection.collapsed(offset: 0),
        ),
      );
      await tester.pump();
      expect(controller.text, over.substring(1));

      // Still over at Save: the stored alt is clipped to fit.
      await tester.tap(_editorSave);
      await pumpFrames(tester);
      expect(strip.attachments.first.alt, over.substring(1, 1001));
    });

    for (final commitBySave in [false, true]) {
      testWidgets('a new word composed at the end of text already over the '
          'limit is dropped on ${commitBySave ? 'Save' : 'commit'}, keeping '
          'the text before it', (tester) async {
        final strip = await pumpStrip(tester);
        await openEditor(tester, 0);
        final over = '${'a' * 999}bcZ'; // 1002 graphemes
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: over,
            selection: TextSelection.collapsed(offset: over.length),
            composing: const TextRange(start: 999, end: 1001),
          ),
        );
        await tester.pump();
        final controller =
            tester.widget<EditableText>(find.byType(EditableText)).controller
              ..selection = TextSelection.collapsed(offset: over.length);
        await tester.pump();
        expect(controller.value.composing, TextRange.empty);

        // Gboard composes the next word at the end.
        final composed = TextEditingValue(
          text: '$over word',
          selection: TextSelection.collapsed(offset: over.length + 5),
          composing: TextRange(start: over.length, end: over.length + 5),
        );
        tester.testTextInput.updateEditingValue(composed);
        await tester.pump();

        if (commitBySave) {
          await tester.tap(_editorSave);
          await pumpFrames(tester);
          expect(tester.takeException(), isNull);
          expect(strip.attachments.first.alt, over.substring(0, 1000));
        } else {
          tester.testTextInput.updateEditingValue(
            composed.copyWith(composing: TextRange.empty),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(controller.text, over);
        }
      });
    }

    testWidgets('a dropped edit that merges the graphemes around it puts the '
        'caret on a boundary', (tester) async {
      await pumpStrip(tester);
      await openEditor(tester, 0);
      const u = '\u{1F1FA}';
      const sFlag = '\u{1F1F8}';
      final over = '${'a' * 1000}$u-$sFlag'; // 1003 graphemes
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: over,
          selection: TextSelection.collapsed(offset: over.length),
          composing: TextRange(start: 1000, end: over.length),
        ),
      );
      await tester.pump();
      final controller =
          tester.widget<EditableText>(find.byType(EditableText)).controller
            ..selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      // Replace "-" with "Y": still over without it, so the insert is
      // dropped and the flag halves meet.
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${'a' * 1000}${u}Y$sFlag',
          selection: const TextSelection.collapsed(offset: 1000 + 2 + 1),
        ),
      );
      await tester.pump();

      expect(controller.text, '${'a' * 1000}$u$sFlag');
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 1000 + 4),
        reason: 'after the merged flag, not between its halves',
      );
    });

    testWidgets('Save mid-composition mid-text at either limit keeps the text '
        'after the composition', (tester) async {
      final rows = [
        (
          name: 'graphemes',
          before: '${'a' * 998}Z',
          composed: 'bc',
          saved: 'b${'a' * 998}Z',
        ),
        (
          name: 'bytes',
          before: '${family * 398}Z',
          composed: '$family$family',
          saved: '${family * 399}Z',
        ),
      ];
      for (final row in rows) {
        final controller = await pumpStrip(tester);
        await openEditor(tester, 0);
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: row.before,
            selection: const TextSelection.collapsed(offset: 0),
          ),
        );
        await tester.pump();
        final length = row.composed.length;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '${row.composed}${row.before}',
            selection: TextSelection.collapsed(offset: length),
            composing: TextRange(start: 0, end: length),
          ),
        );
        await tester.pump();
        await tester.tap(_editorSave);
        await pumpFrames(tester);
        expect(controller.attachments.first.alt, row.saved, reason: row.name);
      }
    });

    /// Puts [before] in the open editor, applies [edit], and returns the
    /// editor's value afterwards.
    Future<TextEditingValue> applyEdit(
      WidgetTester tester,
      TextEditingValue before,
      TextEditingValue edit,
    ) async {
      await pumpStrip(tester);
      await openEditor(tester, 0);
      tester.testTextInput.updateEditingValue(before);
      await tester.pump();
      expect(_editorText(tester), before.text, reason: 'before');
      tester.testTextInput.updateEditingValue(edit);
      await tester.pump();
      return tester
          .widget<EditableText>(find.byType(EditableText))
          .controller
          .value;
    }

    testWidgets('an autocorrect before the caret past the limit keeps the old '
        'text and a caret at or before the edit', (tester) async {
      final value = await applyEdit(
        tester,
        TextEditingValue(
          text: 'helo ${'a' * 995}',
          selection: const TextSelection.collapsed(offset: 5),
        ),
        TextEditingValue(
          text: 'hello ${'a' * 995}',
          selection: const TextSelection.collapsed(offset: 6),
        ),
      );
      expect(value.text, 'helo ${'a' * 995}');
      expect(value.selection.isCollapsed, isTrue, reason: 'collapsed');
      expect(value.selection.baseOffset, inInclusiveRange(4, 5));
    });

    testWidgets('an edit inside a grapheme cluster at the byte limit keeps '
        'the old text without throwing', (tester) async {
      final value = await applyEdit(
        tester,
        TextEditingValue(
          text: family * 400,
          selection: const TextSelection.collapsed(offset: 2),
        ),
        TextEditingValue(
          text:
              '${family.substring(0, 2)}👨${family.substring(2)}'
              '${family * 399}',
          selection: const TextSelection.collapsed(offset: 4),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(value.text, family * 400);
    });

    testWidgets('a clipped edit that merges graphemes puts the caret on a '
        'grapheme boundary', (tester) async {
      final value = await applyEdit(
        tester,
        TextEditingValue(
          text: '🇦x🇧${family * 399}',
          selection: const TextSelection(baseOffset: 2, extentOffset: 3),
        ),
        TextEditingValue(
          text: '🇦$family🇧${family * 399}',
          selection: const TextSelection.collapsed(offset: 13),
        ),
      );
      expect(value.text, '🇦🇧${family * 399}');
      expect(
        value.selection,
        anyOf(
          const TextSelection.collapsed(offset: 0),
          const TextSelection.collapsed(offset: 4),
        ),
      );
    });

    testWidgets('a composition past either limit that commits as different '
        'text keeps the text after the composition', (tester) async {
      final graphemeTail = '${'a' * 998}Z';
      final byteTail = '${family * 398}Z';
      final rows = [
        (
          name: 'graphemes',
          tail: graphemeTail,
          composed: 'bcd',
          committed: 'xcd',
          text: 'x$graphemeTail',
          caret: 1,
        ),
        (
          name: 'bytes',
          tail: byteTail,
          composed: 'b$family$family',
          committed: 'x$family$family',
          text: 'x$family$byteTail',
          caret: 1 + family.length,
        ),
      ];
      for (final row in rows) {
        await pumpStrip(tester);
        await openEditor(tester, 0);
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: row.tail,
            selection: const TextSelection.collapsed(offset: 0),
          ),
        );
        await tester.pump();
        expect(_editorText(tester), row.tail, reason: '${row.name}: before');
        final length = row.composed.length;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '${row.composed}${row.tail}',
            selection: TextSelection.collapsed(offset: length),
            composing: TextRange(start: 0, end: length),
          ),
        );
        await tester.pump();
        expect(
          _editorText(tester),
          '${row.composed}${row.tail}',
          reason: '${row.name}: composing',
        );
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '${row.committed}${row.tail}',
            selection: TextSelection.collapsed(offset: row.committed.length),
          ),
        );
        await tester.pump();
        final value = tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .value;
        expect(value.text, row.text, reason: row.name);
        expect(
          value.selection,
          TextSelection.collapsed(offset: row.caret),
          reason: '${row.name}: caret',
        );
      }
    });

    testWidgets('an edit before an active composition past the limit keeps '
        'the committed text between them', (tester) async {
      final rows = [
        (
          name: 'autocorrect',
          before: TextEditingValue(
            text: 'omw ${'a' * 994}bZ',
            selection: const TextSelection.collapsed(offset: 999),
            composing: const TextRange(start: 998, end: 999),
          ),
          edit: TextEditingValue(
            text: 'On my way! ${'a' * 994}bZ',
            selection: const TextSelection.collapsed(offset: 1006),
          ),
          text: 'On  ${'a' * 994}bZ',
          caret: 3,
        ),
        (
          name: 'paste',
          before: TextEditingValue(
            text: 'H${'a' * 997}bZ',
            selection: const TextSelection.collapsed(offset: 0),
            composing: const TextRange(start: 998, end: 999),
          ),
          edit: TextEditingValue(
            text: 'XYH${'a' * 997}bZ',
            selection: const TextSelection.collapsed(offset: 2),
          ),
          text: 'H${'a' * 997}bZ',
          caret: 0,
        ),
      ];
      for (final row in rows) {
        final value = await applyEdit(tester, row.before, row.edit);
        expect(value.text, row.text, reason: row.name);
        expect(
          value.selection,
          TextSelection.collapsed(offset: row.caret),
          reason: '${row.name}: caret',
        );
      }
    });

    testWidgets('over generated edits, an over-limit edit clips only text new '
        'in the edit', (tester) async {
      final cases = _generatedAltEdits(20261029);
      await pumpStrip(tester);
      await openEditor(tester, 0);
      final failures = <String>[];
      for (final generated in cases) {
        tester.testTextInput.updateEditingValue(generated.before);
        await tester.pump();
        expect(
          _editorText(tester),
          generated.before.text,
          reason: '${generated.name}: before',
        );
        tester.testTextInput.updateEditingValue(generated.edit);
        await tester.pump();
        final value = tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .value;
        final problem = _altEditInvariantProblem(generated, value);
        if (problem != null) {
          failures.add('${generated.name}: $problem');
        }
      }
      expect(cases.length, greaterThanOrEqualTo(200));
      final overLimit = cases
          .where((c) => !AltTextMeasure.of(c.edit.text).isValid)
          .length;
      expect(overLimit, greaterThanOrEqualTo(100), reason: 'over-limit edits');
      expect(
        failures,
        isEmpty,
        reason: '${failures.length} of ${cases.length} generated edits',
      );
    });
  });
}

/// A generated alt edit: `before` goes into the editor, then `edit`. The
/// edit replaced `before.text[regionStart, regionEnd)`, widened to the old
/// composition where the edit touches it; everything outside it is old text
/// the formatter must keep.
typedef _AltEdit = ({
  String name,
  TextEditingValue before,
  TextEditingValue edit,
  int regionStart,
  int regionEnd,
});

const _altFamily = '👨‍👩‍👧‍👦';

/// Edits at or near both alt limits from a fixed [seed]: autocorrects before,
/// after and inside a composition, compositions committed as changed text,
/// pastes at the start, middle and end, and selections inside a cluster.
List<_AltEdit> _generatedAltEdits(int seed) {
  final random = Random(seed);
  final familyBytes = utf8.encode(_altFamily).length;
  const corrections = [
    ('omw', 'On my way!'),
    ('teh', 'the'),
    ('dont', "don't"),
    ('lol', '😂'),
    ('fam', _altFamily),
  ];
  const commits = [
    ('bcd', 'xcd'),
    ('b$_altFamily$_altFamily', 'x$_altFamily$_altFamily'),
    ('hello', 'Hello there'),
  ];
  const pastes = [
    'XY',
    'pasted text',
    '${_altFamily}X',
    '$_altFamily$_altFamily',
    'QQQQQQQQQQQQQQQQQQQQ',
  ];
  const composed = 'bc';
  final edits = <_AltEdit>[];
  for (final bytes in [false, true]) {
    final unit = bytes ? _altFamily : 'a';
    final mode = bytes ? 'bytes' : 'graphemes';
    // Filler that brings [others] to within [slack] of the limit, split into
    // [parts] runs of which those listed in [nonEmpty] hold at least one unit.
    List<String> fill(
      String others,
      int parts, {
      Set<int> nonEmpty = const {},
    }) {
      final measure = AltTextMeasure.of(others);
      final slack = random.nextInt(3);
      final count = bytes
          ? (ImageUploadLimits.altTextMaxBytes - slack - measure.bytes) ~/
                familyBytes
          : ImageUploadLimits.altTextMaxGraphemes - slack - measure.graphemes;
      final counts = [for (var part = 0; part < parts; part++) 0];
      for (final part in nonEmpty) {
        counts[part] = 1;
      }
      for (var left = count - nonEmpty.length; left > 0; left--) {
        counts[random.nextInt(parts)]++;
      }
      return [for (final part in counts) unit * part];
    }

    TextEditingValue commit(String text, int caret) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );

    for (var round = 0; round < 24; round++) {
      final (word, replacement) =
          corrections[random.nextInt(corrections.length)];
      final paste = pastes[random.nextInt(pastes.length)];

      // An autocorrect before the composition, a space apart.
      var p = fill('$word $composed', 3);
      var start = p[0].length + word.length + 1 + p[1].length;
      var end = start + composed.length;
      edits.add((
        name: '$mode $round autocorrect before composition',
        before: TextEditingValue(
          text: '${p[0]}$word ${p[1]}$composed${p[2]}',
          selection: TextSelection.collapsed(offset: end),
          composing: TextRange(start: start, end: end),
        ),
        edit: commit(
          '${p[0]}$replacement ${p[1]}$composed${p[2]}',
          end - word.length + replacement.length,
        ),
        regionStart: p[0].length,
        regionEnd: p[0].length + word.length,
      ));

      // An autocorrect after the composition, a space apart.
      p = fill('$composed $word', 3);
      start = p[0].length;
      end = start + composed.length;
      final wordStart = end + 1 + p[1].length;
      edits.add((
        name: '$mode $round autocorrect after composition',
        before: TextEditingValue(
          text: '${p[0]}$composed ${p[1]}$word${p[2]}',
          selection: TextSelection.collapsed(offset: end),
          composing: TextRange(start: start, end: end),
        ),
        edit: commit(
          '${p[0]}$composed ${p[1]}$replacement${p[2]}',
          wordStart + replacement.length,
        ),
        regionStart: wordStart,
        regionEnd: wordStart + word.length,
      ));

      // An autocorrect of the composing word.
      p = fill(' $word ', 2);
      start = p[0].length + 1;
      end = start + word.length;
      edits.add((
        name: '$mode $round autocorrect inside composition',
        before: TextEditingValue(
          text: '${p[0]} $word ${p[1]}',
          selection: TextSelection.collapsed(offset: end),
          composing: TextRange(start: start, end: end),
        ),
        edit: commit(
          '${p[0]} $replacement ${p[1]}',
          start + replacement.length,
        ),
        regionStart: start,
        regionEnd: end,
      ));

      // A composition typed past the limit commits as changed text.
      final (composing, committed) = commits[random.nextInt(commits.length)];
      p = fill('', 2);
      start = p[0].length;
      end = start + composing.length;
      edits.add((
        name: '$mode $round composition commits changed',
        before: TextEditingValue(
          text: '${p[0]}$composing${p[1]}',
          selection: TextSelection.collapsed(offset: end),
          composing: TextRange(start: start, end: end),
        ),
        edit: commit('${p[0]}$committed${p[1]}', start + committed.length),
        regionStart: start,
        regionEnd: end,
      ));

      // A paste at the start, middle or end, with or without a composition
      // elsewhere.
      final where = ['start', 'middle', 'end'][round % 3];
      final withComposition = random.nextBool();
      final String old;
      final int at;
      var composition = TextRange.empty;
      if (where == 'end') {
        final prefix = withComposition ? 'H$composed' : '';
        p = fill(prefix, 1, nonEmpty: {0});
        old = '$prefix${p[0]}';
        at = old.length;
        if (withComposition) {
          composition = const TextRange(start: 1, end: 1 + composed.length);
        }
      } else {
        final suffix = withComposition ? '${composed}Z' : '';
        p = fill(suffix, 2, nonEmpty: {1, if (where == 'middle') 0});
        if (where == 'start') {
          p = ['', p[0] + p[1]];
        }
        old = '${p[0]}${p[1]}$suffix';
        at = p[0].length;
        if (withComposition) {
          final compositionStart = p[0].length + p[1].length;
          composition = TextRange(
            start: compositionStart,
            end: compositionStart + composed.length,
          );
        }
      }
      edits.add((
        name:
            '$mode $round paste at $where'
            '${withComposition ? ' with a composition' : ''}',
        before: TextEditingValue(
          text: old,
          selection: TextSelection.collapsed(offset: at),
          composing: composition,
        ),
        edit: commit(
          '${old.substring(0, at)}$paste${old.substring(at)}',
          at + paste.length,
        ),
        regionStart: at,
        regionEnd: at,
      ));

      // A selection starting or ending inside a cluster, replaced by a
      // paste.
      p = fill('$_altFamily$_altFamily', 2);
      final clusters = p[0].length;
      // Code-point offsets inside the family cluster.
      const inside = [2, 3, 5, 6, 8, 9];
      final selectionStart = clusters + inside[random.nextInt(inside.length)];
      final selectionEnd = switch (random.nextInt(3)) {
        0 => selectionStart,
        1 =>
          clusters + _altFamily.length + inside[random.nextInt(inside.length)],
        _ => clusters + 2 * _altFamily.length,
      };
      final clustered = '${p[0]}$_altFamily$_altFamily${p[1]}';
      edits.add((
        name: '$mode $round selection inside a cluster',
        before: TextEditingValue(
          text: clustered,
          selection: TextSelection(
            baseOffset: selectionStart,
            extentOffset: selectionEnd,
          ),
        ),
        edit: commit(
          '${clustered.substring(0, selectionStart)}$paste'
          '${clustered.substring(selectionEnd)}',
          selectionStart + paste.length,
        ),
        regionStart: selectionStart,
        regionEnd: selectionEnd,
      ));
    }
  }
  return edits;
}

/// Why [value] breaks the alt edit invariant for [generated], or null: an
/// edit within both limits passes unchanged; for one over a limit, the old
/// text outside the edit region, widened to grapheme boundaries, is kept
/// on both sides, the text is within both limits, and the selection is on
/// grapheme boundaries.
String? _altEditInvariantProblem(_AltEdit generated, TextEditingValue value) {
  final old = generated.before.text;
  final boundaries = [0];
  for (final character in old.characters) {
    boundaries.add(boundaries.last + character.length);
  }
  final keptStart = boundaries.lastWhere((b) => b <= generated.regionStart);
  final keptEnd = boundaries.firstWhere((b) => b >= generated.regionEnd);
  final head = old.substring(0, keptStart);
  final tail = old.substring(keptEnd);
  final text = value.text;
  // An edit within both limits is the platform's to place; it passes as is.
  if (AltTextMeasure.of(generated.edit.text).isValid) {
    return text == generated.edit.text
        ? null
        : 'an edit within the limits changed';
  }
  if (!text.startsWith(head) ||
      !text.endsWith(tail) ||
      head.length + tail.length > text.length) {
    return 'old text outside the edit was dropped';
  }
  if (!AltTextMeasure.of(text).isValid) {
    return 'over a limit';
  }
  final textBoundaries = {0};
  var offset = 0;
  for (final character in text.characters) {
    offset += character.length;
    textBoundaries.add(offset);
  }
  if (!textBoundaries.contains(value.selection.baseOffset) ||
      !textBoundaries.contains(value.selection.extentOffset)) {
    return 'selection ${value.selection} is not on grapheme boundaries';
  }
  return null;
}
