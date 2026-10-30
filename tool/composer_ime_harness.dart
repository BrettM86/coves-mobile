// Composer IME harness: a standalone app for checking FacetEditingController
// against real keyboards on a physical device. It is verification tooling and
// is never imported from lib/.
//
// Run on a connected phone (it installs over the app's dev build):
//   Android: mise exec -- flutter run --flavor dev -t tool/composer_ime_harness.dart
//   iPhone:  mise exec -- flutter run -t tool/composer_ime_harness.dart
//
// Device check script (Samsung with Gboard, and an iPhone). After each step,
// compare the dump with what the field shows. The dumped ranges are in the
// field's current coordinates, including mid-composition:
//   1. Typing with bold armed: tap Bold at a caret, type a few words.
//   2. Swipe-typing a word inside and next to bold text.
//   3. Accepting a suggestion over a half-bold word.
//   4. Typing a misspelling and pressing space: the word stays as typed
//      (autocorrect is off; suggestions are only applied when tapped).
//   5. Dictation into formatted and plain text.
//   6. Gboard Pinyin input. Then compose a word, tap Bold mid-composition and
//      pick a candidate: the whole converted word is bold and Bold stays on.
//   7. iOS Japanese and Korean input. Then tap Bold mid-composition and
//      convert or confirm: the whole composed text is bold and Bold stays on.
//   8. ZWJ emoji and flags typed inside bold text.
//   9. Blocks: quote a few lines (one bar beside each, text not indented),
//      press Enter at the end of a quoted line (the quote continues), Enter
//      on an empty quoted line (the quote ends), then the same with a code
//      block (it continues over empty lines inside it; Enter twice at the
//      end of a code block exits it) and H1-H3 (Enter on an empty heading
//      ends it; Enter at the start of a heading keeps the heading on the
//      text). Backspace at the start of a line joins it into the line
//      above, which keeps the upper line's formats. Android Back closes
//      the keyboard and drops the caret; switching to another app and
//      back keeps it. Selecting a word highlights only the word.
//  10. Paste multi-line text inside a quote and a code block: it arrives
//      unformatted and each pasted line follows the Enter rule.
// Ranges that drift in a way the diff logic cannot fix stop the loop for a
// super_editor re-plan.

import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ComposerImeHarnessApp());
}

class ComposerImeHarnessApp extends StatelessWidget {
  const ComposerImeHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Composer IME harness',
      theme: ThemeData.dark(),
      home: const ComposerImeHarnessScreen(),
    );
  }
}

class ComposerImeHarnessScreen extends StatefulWidget {
  const ComposerImeHarnessScreen({super.key});

  @override
  State<ComposerImeHarnessScreen> createState() =>
      _ComposerImeHarnessScreenState();
}

class _ComposerImeHarnessScreenState extends State<ComposerImeHarnessScreen> {
  final FacetEditingController _controller = FacetEditingController();
  final FocusNode _focusNode = FocusNode();

  /// Focus nodes that cannot take focus, so tapping a button leaves the
  /// keyboard and the composing region on the field.
  final Map<InlineFormat, FocusNode> _formatButtonNodes = {
    for (final format in InlineFormat.values)
      format: FocusNode(canRequestFocus: false, skipTraversal: true),
  };
  final FocusNode _clearButtonNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );
  final Map<String, FocusNode> _blockButtonNodes = {
    for (final name in ['quote', 'H1', 'H2', 'H3', 'code block'])
      name: FocusNode(canRequestFocus: false, skipTraversal: true),
  };

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    for (final node in _formatButtonNodes.values) {
      node.dispose();
    }
    _clearButtonNode.dispose();
    for (final node in _blockButtonNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  String _dump(TextEditingValue value) {
    final active = _controller.activeInlineFormats().map(
      (format) => format.name,
    );
    final ranges = _controller.inlineRanges.map(
      (range) => '  ${range.format.name} [${range.start}, ${range.end})',
    );
    final blocks = _controller.blockRanges.map(
      (range) =>
          '  ${range.format.name} L${range.level} '
          '[${range.start}, ${range.end})',
    );
    return [
      'length: ${value.text.length}',
      'selection: [${value.selection.start}, ${value.selection.end})',
      'composing: [${value.composing.start}, ${value.composing.end})',
      'active: {${active.join(', ')}}',
      'inlineRanges:',
      if (ranges.isEmpty) '  (none)' else ...ranges,
      'blockRanges:',
      if (blocks.isEmpty) '  (none)' else ...blocks,
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Composer IME harness')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FacetTextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              autocorrect: false,
              minLines: 4,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final active = _controller.activeInlineFormats();
                final inCode = _controller.isSelectionInCodeBlock();
                final activeBlocks = _controller.activeBlockFormats();
                final headingLevel = _controller.activeHeadingLevel();
                // Taps inside the tap region count as taps on the field, so
                // they do not unfocus it.
                return TextFieldTapRegion(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final format in InlineFormat.values)
                        FilterChip(
                          label: Text(format.name),
                          selected: active.contains(format),
                          focusNode: _formatButtonNodes[format],
                          onSelected: inCode
                              ? null
                              : (_) => _controller.toggleInline(format),
                        ),
                      FilterChip(
                        label: const Text('quote'),
                        selected: activeBlocks.contains(BlockFormat.blockquote),
                        focusNode: _blockButtonNodes['quote'],
                        onSelected: (_) =>
                            _controller.toggleBlock(BlockFormat.blockquote),
                      ),
                      for (final level in [1, 2, 3])
                        FilterChip(
                          label: Text('H$level'),
                          selected: headingLevel == level,
                          focusNode: _blockButtonNodes['H$level'],
                          onSelected: (_) => _controller.toggleBlock(
                            BlockFormat.heading,
                            level: level,
                          ),
                        ),
                      FilterChip(
                        label: const Text('code block'),
                        selected: activeBlocks.contains(BlockFormat.codeBlock),
                        focusNode: _blockButtonNodes['code block'],
                        onSelected: (_) =>
                            _controller.toggleBlock(BlockFormat.codeBlock),
                      ),
                      ActionChip(
                        label: const Text('clear'),
                        focusNode: _clearButtonNode,
                        onPressed: _controller.clear,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) => SelectableText(
                _dump(value),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['Menlo', 'Courier New', 'Courier'],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
