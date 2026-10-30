import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:coves_flutter/screens/home/create_post_screen.dart';
import 'package:coves_flutter/screens/home/post_detail_screen.dart';
import 'package:coves_flutter/services/api_exceptions.dart';
import 'package:coves_flutter/widgets/composer/facet_block_painter.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:coves_flutter/widgets/composer/formatting_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../test_helpers/facet_description.dart';
import '../../test_helpers/test_mocks.dart';
import '../../widgets/composer/clipboard_test_helpers.dart';
import '../../widgets/composer/formatting_toolbar_test_helpers.dart';
import '../../widgets/composer/span_style_helpers.dart';
import 'create_post_test_harness.dart';

/// The namespace every Coves facet feature type is under
const _facet = 'social.coves.richtext.facet';

void main() {
  late FakeAuthProvider fakeAuthProvider;
  late MockCovesApiService mockApiService;

  setUp(() {
    fakeAuthProvider = FakeAuthProvider();
    mockApiService = MockCovesApiService();
    stubOneCommunity(mockApiService);
  });

  Future<void> pumpScreen(WidgetTester tester) =>
      pumpCreatePostWithPostDetailProviders(
        tester,
        auth: fakeAuthProvider,
        api: mockApiService,
      );

  /// The title's editable text
  final titleEditable = find.descendant(
    of: find.widgetWithText(TextField, 'Title'),
    matching: find.byType(EditableText),
  );

  /// The text the body renders, as laid out
  TextSpan bodySpan(WidgetTester tester) =>
      tester.state<EditableTextState>(bodyEditable).renderEditable.text!
          as TextSpan;

  /// Taps Post and pumps a bounded number of frames: the Post spinner keeps
  /// animating under post detail, so pumpAndSettle would never return
  Future<void> tapPost(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Post'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  group('CreatePostScreen formatting toolbar', () {
    toolbarTest('body focused: the formatting toolbar shows over a '
        'FacetTextField with autocorrect off and suggestions on', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.showKeyboard(bodyEditable);
      await tester.pump();

      expect(button('Bold'), findsOneWidget);
      expect(find.byType(FormattingToolbar), findsOneWidget);

      bodyFacetField(tester);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(FacetTextField),
          matching: find.byType(TextField),
        ),
      );
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isTrue);
    });

    toolbarTest('the toolbar shows only while the body is focused; the title '
        'stays a plain TextField', (tester) async {
      await pumpScreen(tester);

      await tester.showKeyboard(bodyEditable);
      await tester.pump();
      expect(button('Bold'), findsOneWidget, reason: 'body focused');

      await tester.showKeyboard(titleEditable);
      await tester.pump();
      expect(button('Bold'), findsNothing, reason: 'title focused');
      expect(find.byType(FormattingToolbar), findsNothing);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(button('Bold'), findsNothing, reason: 'nothing focused');
      expect(find.byType(FormattingToolbar), findsNothing);

      expect(
        find.ancestor(
          of: find.widgetWithText(TextField, 'Title'),
          matching: find.byType(FacetTextField),
        ),
        findsNothing,
        reason: 'the title is not a FacetTextField',
      );
    });

    toolbarTest('with the keyboard open, the toolbar sits fully on screen '
        'right on top of the keyboard', (tester) async {
      const keyboardHeight = 300.0;
      addTearDown(tester.view.resetViewInsets);
      await pumpScreen(tester);
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeight * tester.view.devicePixelRatio,
      );
      await tester.pump();
      await tester.showKeyboard(bodyEditable);
      await tester.pumpAndSettle();

      expect(find.byType(FormattingToolbar), findsOneWidget);
      final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
      final keyboardTop = viewSize.height - keyboardHeight;
      final toolbar = tester.getRect(find.byType(FormattingToolbar));
      expect(toolbar.top, greaterThanOrEqualTo(0));
      expect(toolbar.left, greaterThanOrEqualTo(0));
      expect(toolbar.right, lessThanOrEqualTo(viewSize.width));
      expect(toolbar.bottom, lessThanOrEqualTo(keyboardTop));
      expect(toolbar.bottom, greaterThanOrEqualTo(keyboardTop - 1));
    });
  });

  group('CreatePostScreen formats from the toolbar', () {
    // Each format applied over all of 'hello': the facet it sends
    const rows = [
      (label: 'Bold', facet: '[0,5) [{"\$type":"$_facet#bold"}]'),
      (label: 'Italic', facet: '[0,5) [{"\$type":"$_facet#italic"}]'),
      (
        label: 'Strikethrough',
        facet: '[0,5) [{"\$type":"$_facet#strikethrough"}]',
      ),
      (label: 'Spoiler', facet: '[0,5) [{"\$type":"$_facet#spoiler"}]'),
      (label: 'Code', facet: '[0,5) [{"\$type":"$_facet#code"}]'),
      (label: 'Quote', facet: '[0,5) [{"\$type":"$_facet#blockquote"}]'),
      (
        label: 'Heading 1',
        facet: '[0,5) [{"\$type":"$_facet#heading","level":1}]',
      ),
      (label: 'Code block', facet: '[0,5) [{"\$type":"$_facet#codeBlock"}]'),
    ];

    for (final row in rows) {
      toolbarTest('${row.label} shows in the body and is sent as its facet', (
        tester,
      ) async {
        // Recorded, then thrown, so the screen stays put
        when(
          mockApiService.createPost(
            community: anyNamed('community'),
            title: anyNamed('title'),
            content: anyNamed('content'),
            facets: anyNamed('facets'),
            embed: anyNamed('embed'),
            langs: anyNamed('langs'),
            labels: anyNamed('labels'),
          ),
        ).thenThrow(ApiException('recorded'));
        await pumpScreen(tester);
        await selectCommunity(tester);
        await tester.enterText(bodyEditable, 'hello');
        await focusField(
          tester,
          const TextSelection(baseOffset: 0, extentOffset: 5),
          field: bodyEditable,
        );
        final plainStyles = characterStylesOf(bodySpan(tester), 'hello');

        if (row.label == 'Heading 1') {
          await openPicker(tester);
          await pickEntry(tester, 'Heading 1');
        } else {
          await tapButton(tester, row.label);
        }

        if (row.label == 'Quote') {
          // A quote is drawn by the field's block painter, not as a style
          final painters = tester
              .widgetList<CustomPaint>(
                find.descendant(
                  of: find.byType(FacetTextField),
                  matching: find.byType(CustomPaint),
                ),
              )
              .map((paint) => paint.foregroundPainter)
              .whereType<FacetBlockPainter>()
              .toList();
          expect(painters, hasLength(1));
          expect(painters.single.layer, FacetBlockLayer.quoteBars);
          final quotes = painters.single.controller.blockRanges;
          expect(quotes, hasLength(1));
          expect(quotes.single.format, BlockFormat.blockquote);
          expect(quotes.single.start, 0);
          expect(quotes.single.end, 5);
        } else {
          final styles = characterStylesOf(bodySpan(tester), 'hello');
          for (var i = 0; i < 5; i++) {
            expect(
              styles[i],
              isNot(plainStyles[i]),
              reason: 'character $i of hello shows ${row.label}',
            );
          }
        }

        await tester.tap(find.widgetWithText(TextButton, 'Post'));
        await tester.pumpAndSettle();

        final (content, facets) = captureCreatePostContentAndFacets(
          mockApiService,
        );
        expect(content, 'hello');
        expect(facets?.map(describeFacet).toList(), [row.facet]);
      });
    }
  });

  group('CreatePostScreen submit with formatting and mentions', () {
    toolbarTest('sends trimmed content with the formatting facets and the '
        'resolved mention, nothing inside inline code is looked up or '
        'linked, and the optimistic post carries the same', (tester) async {
      when(mockApiService.resolveHandle(handle: 'alice.test'))
          .thenAnswer((_) async => 'did:plc:alice');
      when(mockApiService.resolveHandle(handle: 'bob.test'))
          .thenAnswer((_) async => 'did:plc:bob');
      stubCreatePostSucceeds(mockApiService);
      await pumpScreen(tester);
      await selectCommunity(tester);

      // UTF-16 offsets: 'Hi' [2,4), '@bob.test https://x.com' [17,40)
      await tester.enterText(
        bodyEditable,
        '  Hi @alice.test @bob.test https://x.com\n',
      );
      await focusField(
        tester,
        const TextSelection(baseOffset: 2, extentOffset: 4),
        field: bodyEditable,
      );
      await tapButton(tester, 'Bold');
      await focusField(
        tester,
        const TextSelection(baseOffset: 17, extentOffset: 40),
        field: bodyEditable,
      );
      await tapButton(tester, 'Code');

      await tapPost(tester);

      const expectedFacets = [
        '[0,2) [{"\$type":"$_facet#bold"}]',
        '[3,14) [{"\$type":"$_facet#mention","did":"did:plc:alice"}]',
        '[15,38) [{"\$type":"$_facet#code"}]',
      ];
      final (content, facets) = captureCreatePostContentAndFacets(
        mockApiService,
      );
      expect(content, 'Hi @alice.test @bob.test https://x.com');
      expect(
        facets?.map(describeFacet).toList(),
        unorderedEquals(expectedFacets),
      );
      verifyNever(mockApiService.resolveHandle(handle: 'bob.test'));

      final detail = tester.widget<PostDetailScreen>(
        find.byType(PostDetailScreen),
      );
      expect(detail.isOptimistic, isTrue);
      final record = detail.post.post.record;
      expect(record?.content, 'Hi @alice.test @bob.test https://x.com');
      expect(
        record?.facets?.map(describeFacet).toList(),
        unorderedEquals(expectedFacets),
      );
    });
  });

  group('CreatePostScreen submit snapshot', () {
    toolbarTest('edits to the body and its formatting while a mention lookup '
        'is pending reach neither the request nor the optimistic post', (
      tester,
    ) async {
      final lookup = Completer<String>();
      when(mockApiService.resolveHandle(handle: 'alice.test'))
          .thenAnswer((_) => lookup.future);
      stubCreatePostSucceeds(mockApiService);
      await pumpScreen(tester);
      await selectCommunity(tester);

      await tester.enterText(bodyEditable, 'Hi @alice.test');
      await focusField(
        tester,
        const TextSelection(baseOffset: 0, extentOffset: 2),
        field: bodyEditable,
      );
      await tapButton(tester, 'Bold');

      await tapPost(tester);

      // While the lookup is pending: bold off, italic on, more text
      await focusField(
        tester,
        const TextSelection(baseOffset: 0, extentOffset: 2),
        field: bodyEditable,
      );
      await tapButton(tester, 'Bold');
      await tapButton(tester, 'Italic');
      await typeAs(tester, 'Hi @alice.test and more', 23);
      expect(bodyController(tester).text, 'Hi @alice.test and more');

      lookup.complete('did:plc:alice');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      const expectedFacets = [
        '[0,2) [{"\$type":"$_facet#bold"}]',
        '[3,14) [{"\$type":"$_facet#mention","did":"did:plc:alice"}]',
      ];
      final (content, facets) = captureCreatePostContentAndFacets(
        mockApiService,
      );
      expect(content, 'Hi @alice.test');
      expect(
        facets?.map(describeFacet).toList(),
        unorderedEquals(expectedFacets),
      );

      final detail = tester.widget<PostDetailScreen>(
        find.byType(PostDetailScreen),
      );
      expect(detail.isOptimistic, isTrue);
      final record = detail.post.post.record;
      expect(record?.content, 'Hi @alice.test');
      expect(
        record?.facets?.map(describeFacet).toList(),
        unorderedEquals(expectedFacets),
      );
    });
  });

  group('CreatePostScreen reset after posting', () {
    toolbarTest('after a successful post and returning from post detail, the '
        'body has no text, no ranges and nothing armed', (tester) async {
      stubCreatePostSucceeds(mockApiService);
      await pumpScreen(tester);
      await selectCommunity(tester);

      await tester.enterText(bodyEditable, 'hello');
      await focusField(
        tester,
        const TextSelection(baseOffset: 0, extentOffset: 5),
        field: bodyEditable,
      );
      await tapButton(tester, 'Bold');
      await tapButton(tester, 'Quote');
      // A collapsed caret after the bold text arms Bold for the next typing
      await focusField(
        tester,
        const TextSelection.collapsed(offset: 5),
        field: bodyEditable,
      );
      expect(selectedState(tester, 'Bold'), Tristate.isTrue);

      await tapPost(tester);
      expect(find.byType(PostDetailScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(PostDetailScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(PostDetailScreen), findsNothing);
      expect(find.byType(CreatePostScreen), findsOneWidget);

      final controller = bodyController(tester);
      expect(controller.text, '');
      expect(controller.inlineRanges, isEmpty);
      expect(controller.blockRanges, isEmpty);
      expect(controller.featureRanges, isEmpty);

      await tester.showKeyboard(bodyEditable);
      await tester.pump();
      for (final label in [
        'Bold',
        'Italic',
        'Strikethrough',
        'Spoiler',
        'Code',
        'Quote',
        'Code block',
      ]) {
        expect(
          selectedState(tester, label),
          isNot(Tristate.isTrue),
          reason: '$label is not active after the reset',
        );
      }

      await typeAs(tester, 'x', 1);
      expect(controller.text, 'x');
      expect(controller.inlineRanges, isEmpty);
      expect(controller.blockRanges, isEmpty);
      expect(controller.featureRanges, isEmpty);
    });

    toolbarTest('a format armed in the empty body is disarmed after a '
        'title-only post', (tester) async {
      stubCreatePostSucceeds(mockApiService);
      await pumpScreen(tester);
      await selectCommunity(tester);

      await focusField(
        tester,
        const TextSelection.collapsed(offset: 0),
        field: bodyEditable,
      );
      await tapButton(tester, 'Bold');
      expect(
        selectedState(tester, 'Bold'),
        Tristate.isTrue,
        reason: 'precondition: Bold is armed in the empty body',
      );
      await tester.enterText(titleEditable, 'Title only');
      await tester.pump();

      await tapPost(tester);
      expect(find.byType(PostDetailScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(PostDetailScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(CreatePostScreen), findsOneWidget);

      final controller = bodyController(tester);
      expect(controller.text, '');
      expect(controller.activeInlineFormats(), isEmpty);

      await tester.showKeyboard(bodyEditable);
      await tester.pump();
      for (final label in [
        'Bold',
        'Italic',
        'Strikethrough',
        'Spoiler',
        'Code',
        'Quote',
        'Code block',
      ]) {
        expect(
          selectedState(tester, label),
          isNot(Tristate.isTrue),
          reason: '$label is not active after the reset',
        );
      }

      await typeAs(tester, 'x', 1);
      expect(controller.text, 'x');
      expect(controller.inlineRanges, isEmpty);
    });
  });

  group('CreatePostScreen blocked submits keep the formatted body', () {
    toolbarTest('a mention lookup failure other than not-found blocks the '
        'post and keeps the body text and formatting', (tester) async {
      when(mockApiService.resolveHandle(handle: 'alice.test')).thenAnswer(
        (_) => Future<String>.error(
          ServerException('Mention lookup unavailable', statusCode: 503),
        ),
      );
      await pumpScreen(tester);
      await selectCommunity(tester);

      await tester.enterText(bodyEditable, 'Hi @alice.test');
      await focusField(
        tester,
        const TextSelection(baseOffset: 0, extentOffset: 2),
        field: bodyEditable,
      );
      await tapButton(tester, 'Bold');

      await tester.tap(find.widgetWithText(TextButton, 'Post'));
      await tester.pumpAndSettle();

      verifyNever(
        mockApiService.createPost(
          community: anyNamed('community'),
          title: anyNamed('title'),
          content: anyNamed('content'),
          facets: anyNamed('facets'),
          embed: anyNamed('embed'),
          langs: anyNamed('langs'),
          labels: anyNamed('labels'),
        ),
      );
      expect(find.byType(SnackBar), findsOneWidget);

      final controller = bodyController(tester);
      expect(controller.text, 'Hi @alice.test');
      expect(controller.inlineRanges, hasLength(1));
      expect(controller.inlineRanges.single.format, InlineFormat.bold);
      expect(controller.inlineRanges.single.start, 0);
      expect(controller.inlineRanges.single.end, 2);
      expect(controller.blockRanges, isEmpty);
    });

    testWidgets('formatting over 200 facets blocks the post with the '
        'over-limit message and keeps the text and formatting', (tester) async {
      stubCreatePostSucceeds(mockApiService);
      await pumpScreen(tester);
      await selectCommunity(tester);

      // Toggles stop at the budget, plain edits do not: bold 201 letters as
      // one range, then split it 200 times by typing an unbolded space after
      // each letter with Bold toggled off at the caret. The result is 201
      // letters apart by spaces, each bold on its own: 201 facets
      final controller = bodyController(tester)
        ..value = TextEditingValue(
          text: 'a' * 201,
          selection: const TextSelection(baseOffset: 0, extentOffset: 201),
        )
        ..toggleInline(InlineFormat.bold);
      for (var split = 0; split < 200; split++) {
        final caret = 2 * split + 1;
        controller
          ..selection = TextSelection.collapsed(offset: caret)
          ..toggleInline(InlineFormat.bold);
        final text = controller.text;
        controller.value = TextEditingValue(
          text: '${text.substring(0, caret)} ${text.substring(caret)}',
          selection: TextSelection.collapsed(offset: caret + 1),
        );
      }
      await tester.pump();
      final text = List.filled(201, 'a').join(' ');
      expect(controller.text, text);
      expect(controller.inlineRanges, hasLength(201));

      await tester.tap(find.widgetWithText(TextButton, 'Post'));
      await tester.pumpAndSettle();

      verifyNever(
        mockApiService.createPost(
          community: anyNamed('community'),
          title: anyNamed('title'),
          content: anyNamed('content'),
          facets: anyNamed('facets'),
          embed: anyNamed('embed'),
          langs: anyNamed('langs'),
          labels: anyNamed('labels'),
        ),
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'Too much formatting to send. Remove some and try again.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Could not create post. Please try again.'),
        findsNothing,
      );

      expect(controller.text, text);
      final ranges = controller.inlineRanges;
      expect(ranges, hasLength(201));
      for (var index = 0; index < 201; index++) {
        expect(ranges[index].format, InlineFormat.bold, reason: 'range $index');
        expect(ranges[index].start, 2 * index, reason: 'range $index start');
        expect(ranges[index].end, 2 * index + 1, reason: 'range $index end');
      }
    });
  });

  group('CreatePostScreen body length limit', () {
    testWidgets('a clipboard paste stops at the 10000-character limit', (
      tester,
    ) async {
      installClipboard(tester, text: 'xyz');
      await pumpScreen(tester);
      await tester.enterText(bodyEditable, 'a' * 9998);
      await tester.pump();

      await pressWithControl(tester, LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();

      expect(
        tester.widget<EditableText>(bodyEditable).controller.text,
        '${'a' * 9998}xy',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
