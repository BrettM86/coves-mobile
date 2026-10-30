import 'package:coves_flutter/models/facet.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';

/// A large, fully formatted composer draft for measuring editor performance.
///
/// [text] is exactly 10000 UTF-16 units and carries 200 ranges with distinct
/// bounds (so it serializes to the 200-facet record maximum) spread across
/// the whole text: every inline and block format, headings H1 to H6, mentions
/// and links, a heading and a code block inside a quote, and inline ranges
/// around a ZWJ emoji and a combining sequence. The ranges are canonical, so
/// [FacetEditingController.withRanges] loads them unchanged. [editOffset] is a
/// plain word boundary near the quoted heading and code block, where a
/// harness types to exercise remapping and layout.
class PerfFixture {
  const PerfFixture({
    required this.text,
    required this.inlineRanges,
    required this.blockRanges,
    required this.featureRanges,
    required this.editOffset,
  });

  final String text;
  final List<InlineRange> inlineRanges;
  final List<BlockRange> blockRanges;
  final List<FeatureRange> featureRanges;
  final int editOffset;
}

const _fixtureLength = 10000;
const _rangeCount = 200;

/// Builds the [PerfFixture] deterministically.
///
/// Shared by the composer unit tests and the profile-mode integration perf
/// harness, so it must not depend on flutter_test.
PerfFixture buildPerfFixture() {
  final paragraphs = <_Paragraph>[_graphemeParagraph()];
  var rangeCount = paragraphs.first.rangeCount;
  final quotedBlocks = _quotedBlocksParagraph();
  final detectable = _detectableParagraph();
  rangeCount += quotedBlocks.rangeCount + detectable.rangeCount;

  final builders = <_Paragraph Function(int)>[
    _inlineParagraph,
    _headingParagraph,
    _quoteParagraph,
    _codeParagraph,
  ];
  final cycle = <_Paragraph>[];
  for (var index = 0; ; index++) {
    final paragraph = builders[index % builders.length](
      index ~/ builders.length,
    );
    if (rangeCount + paragraph.rangeCount > _rangeCount) {
      break;
    }
    cycle.add(paragraph);
    rangeCount += paragraph.rangeCount;
  }
  final middle = cycle.length ~/ 2;
  paragraphs
    ..addAll(cycle.take(middle))
    ..add(quotedBlocks)
    ..addAll(cycle.skip(middle))
    ..add(_topUpParagraph(_rangeCount - rangeCount))
    ..add(detectable);

  const closing = 'Thanks for reading this far.';
  final unpadded =
      paragraphs.fold(0, (length, paragraph) => length + paragraph.length) +
      closing.length;
  final padding = _fixtureLength - unpadded;
  if (padding < 0) {
    throw StateError('perf fixture paragraphs exceed $_fixtureLength units');
  }

  final text = StringBuffer();
  final inlineRanges = <InlineRange>[];
  final blockRanges = <BlockRange>[];
  final featureRanges = <FeatureRange>[];
  int? editOffset;
  for (final (index, paragraph) in paragraphs.indexed) {
    final offset = text.length;
    text.write(paragraph.text);
    inlineRanges.addAll([
      for (final range in paragraph.inlineRanges)
        InlineRange(
          range.format,
          range.start + offset,
          range.end + offset,
          reason: range.reason,
        ),
    ]);
    blockRanges.addAll([
      for (final range in paragraph.blockRanges)
        BlockRange(
          range.format,
          range.start + offset,
          range.end + offset,
          level: range.level,
          language: range.language,
        ),
    ]);
    featureRanges.addAll([
      for (final range in paragraph.featureRanges)
        FeatureRange(range.feature, range.start + offset, range.end + offset),
    ]);
    final editMark = paragraph.editMark;
    if (editMark != null) {
      editOffset = offset + editMark;
    }
    // Spread the padding as plain filler lines after each paragraph.
    final fillerLength =
        padding ~/ paragraphs.length +
        (index < padding % paragraphs.length ? 1 : 0);
    if (fillerLength > 0) {
      text
        ..write(_filler(fillerLength - 1))
        ..write('\n');
    }
  }
  text.write(closing);

  return PerfFixture(
    text: text.toString(),
    inlineRanges: inlineRanges,
    blockRanges: blockRanges,
    featureRanges: featureRanges,
    editOffset: editOffset!,
  );
}

/// Plain prose of exactly [length] units, free of sigils and URLs.
String _filler(int length) {
  const words =
      'the quiet harbor wakes slowly while gulls circle the old pier and '
      'fishermen mend their nets beside the painted sheds before the ferry '
      'leaves for the islands across the bay ';
  final buffer = StringBuffer();
  while (buffer.length < length) {
    buffer.write(words);
  }
  return buffer.toString().substring(0, length);
}

/// One paragraph of the fixture, with ranges in its own offsets.
class _Paragraph {
  final StringBuffer _text = StringBuffer();
  final List<InlineRange> inlineRanges = [];
  final List<BlockRange> blockRanges = [];
  final List<FeatureRange> featureRanges = [];
  int? editMark;

  String get text => _text.toString();

  int get length => _text.length;

  int get rangeCount =>
      inlineRanges.length + blockRanges.length + featureRanges.length;

  void plain(String value) => _text.write(value);

  void inline(InlineFormat format, String value, {String? reason}) {
    final start = _text.length;
    _text.write(value);
    inlineRanges.add(InlineRange(format, start, _text.length, reason: reason));
  }

  void mention(String handle, String did) {
    final start = _text.length;
    _text.write('@$handle');
    featureRanges.add(
      FeatureRange(MentionFacetFeature(did: did), start, _text.length),
    );
  }

  void link(String label, String uri) {
    final start = _text.length;
    _text.write(label);
    featureRanges.add(
      FeatureRange(LinkFacetFeature(uri: uri), start, _text.length),
    );
  }

  void line(String value) => _text
    ..write(value)
    ..write('\n');

  void endLine() => _text.write('\n');

  void heading(int level, String value) {
    final start = _text.length;
    _text.write(value);
    blockRanges.add(
      BlockRange(BlockFormat.heading, start, _text.length, level: level),
    );
    endLine();
  }

  void codeBlock(List<String> lines, {String? language}) {
    final start = _text.length;
    _text.write(lines.join('\n'));
    blockRanges.add(
      BlockRange(
        BlockFormat.codeBlock,
        start,
        _text.length,
        language: language,
      ),
    );
    endLine();
  }

  /// Quotes the whole lines [body] writes; [body] must end with a newline.
  void quote(void Function() body) {
    final start = _text.length;
    body();
    blockRanges.add(
      BlockRange(BlockFormat.blockquote, start, _text.length - 1),
    );
  }
}

/// Eight inline ranges over one prose line.
_Paragraph _inlineParagraph(int index) => _Paragraph()
  ..plain('Day ${index + 1} on the water: ')
  ..inline(InlineFormat.bold, 'the tide turned early')
  ..plain(', ')
  ..inline(InlineFormat.italic, 'gulls followed the boat')
  ..plain(', and ')
  ..inline(InlineFormat.strikethrough, 'the forecast was wrong')
  ..plain('. Ask about ')
  ..inline(
    InlineFormat.spoiler,
    'the hidden cove',
    reason: index.isEven ? 'plot' : null,
  )
  ..plain(' or run ')
  ..inline(InlineFormat.code, 'tide --today')
  ..plain('. Then ')
  ..inline(InlineFormat.italic, 'we rested')
  ..plain(' near ')
  ..inline(InlineFormat.bold, 'the lighthouse')
  ..plain(' until ')
  ..inline(InlineFormat.strikethrough, 'noon')
  ..line('.');

/// A heading (levels 1 to 6 in turn) and a line with a mention and a link.
_Paragraph _headingParagraph(int index) => _Paragraph()
  ..heading(index % 6 + 1, 'Chapter ${index + 1}: notes from the north shore')
  ..plain('Spoke with ')
  ..mention('sailor$index.test', 'did:plc:perffixturesailor$index')
  ..plain(' about the route; details are in ')
  ..link('the harbor guide', 'https://example.com/guide/$index')
  ..line('.');

/// A plain line, then a two-line quote with inline formatting.
_Paragraph _quoteParagraph(int index) {
  final paragraph = _Paragraph()..line('Neighbour ${index + 1} wrote:');
  return paragraph..quote(() {
    paragraph
      ..plain('The boats came in late and ')
      ..inline(InlineFormat.italic, 'everyone')
      ..line(' waited on the pier.')
      ..inline(InlineFormat.bold, 'Nobody')
      ..line(' minded the rain that evening.');
  });
}

/// A code block between plain lines, the closing one with a bold range.
_Paragraph _codeParagraph(int index) => _Paragraph()
  ..line('Here is log format ${index + 1}:')
  ..codeBlock([
    'entry $index: high 06:12 1.8m',
    'entry $index: low 12:40 0.3m',
    'entry $index: high 18:55 1.7m',
  ], language: index.isEven ? 'text' : null)
  ..plain('That format kept ')
  ..inline(InlineFormat.bold, 'every entry')
  ..line(' easy to read.');

/// Inline ranges strictly around a combining sequence and a ZWJ emoji.
_Paragraph _graphemeParagraph() => _Paragraph()
  ..plain('We met at the ')
  ..inline(InlineFormat.bold, 'café corner')
  ..plain(' and took a ')
  ..inline(InlineFormat.italic, 'family \u{1F468}‍\u{1F469}‍\u{1F467} photo')
  ..line(' by the water.');

/// The edit point, then a quote holding a heading and a code block.
_Paragraph _quotedBlocksParagraph() {
  final paragraph = _Paragraph()..plain('Before the quote, a ');
  paragraph
    ..editMark = paragraph.length
    ..line('plain line to edit in the middle of the draft.');
  return paragraph..quote(() {
    paragraph
      ..line('Quoted reply from the harbor master:')
      ..heading(3, 'Tide tables for the week')
      ..line('The numbers below are from the morning log.')
      ..codeBlock(['high 06:12 1.8m', 'low 12:40 0.3m'], language: 'text')
      ..line('End of the quoted log.');
  });
}

/// A mention and a link left as plain text for detection to find.
_Paragraph _detectableParagraph() => _Paragraph()
  ..line(
    'Plain text still links: say hi to @harbor.test or read '
    'https://example.com/plain-notes today.',
  );

/// [count] italic words on one line, to land on the exact range total.
_Paragraph _topUpParagraph(int count) {
  final paragraph = _Paragraph()..plain('Last words:');
  for (var index = 0; index < count; index++) {
    paragraph
      ..plain(' ')
      ..inline(InlineFormat.italic, 'word$index');
  }
  return paragraph..line('.');
}
