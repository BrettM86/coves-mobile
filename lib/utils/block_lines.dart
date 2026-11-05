/// Extends a block facet's char range [charStart, charEnd) to whole lines
///
/// Per the lexicon, block ranges must span whole lines excluding the
/// trailing newline; readers extend malformed mid-line ranges outward.
/// Returns null when nothing but newlines is covered.
(int, int)? lineExtendedRange(String text, int charStart, int charEnd) {
  // A sloppy writer may start the range on a newline; advance past leading
  // newlines before snapping to line start so we don't swallow the previous
  // line (symmetric with the trailing back-off below).
  var rangeStart = charStart;
  while (rangeStart < charEnd && text[rangeStart] == '\n') {
    rangeStart++;
  }

  final start = rangeStart == 0
      ? 0
      : text.lastIndexOf('\n', rangeStart - 1) + 1;

  // A sloppy writer may include the trailing newline; back off before
  // extending forward so we don't swallow the next line.
  var end = charEnd;
  while (end > start && text[end - 1] == '\n') {
    end--;
  }
  if (end < text.length && text[end] != '\n') {
    final nl = text.indexOf('\n', end);
    end = nl == -1 ? text.length : nl;
  }

  return end > start ? (start, end) : null;
}
