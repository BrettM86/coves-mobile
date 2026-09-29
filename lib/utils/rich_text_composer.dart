import 'dart:convert';

import '../models/facet.dart';
import 'url_policy.dart';
import 'utf8_offsets.dart';

/// Content ready to send, with the link facets detected in it
class ComposedRichText {
  const ComposedRichText._({required this.content, this.facets});

  /// Canonical content to send
  final String content;

  /// Link facets over [content], or null when there are none
  final List<RichTextFacet>? facets;
}

/// Trims [text] and detects the bare http(s) URLs in it as link facets
///
/// Produces the canonical content and link facets the backend validates: the
/// facet byte ranges are UTF-8 offsets into the trimmed
/// [ComposedRichText.content], so trimming must happen before any range is
/// measured.
ComposedRichText composeRichText(String text) {
  final content = text.trim();
  final offsets = Utf8Offsets(content);

  final facets = <RichTextFacet>[];
  for (final match in _urlCandidate.allMatches(content)) {
    // Links past the backend's facet cap are left as plain text
    if (facets.length == maxFacetsPerRecord) {
      break;
    }
    final link = _acceptedLink(content, match.start, match.end);
    if (link == null) {
      continue;
    }
    final (:start, :end, :uri) = link;
    facets.add(
      RichTextFacet(
        index: ByteSlice(
          byteStart: offsets.byteOffsetOf(start),
          byteEnd: offsets.byteOffsetOf(end),
        ),
        features: [LinkFacetFeature(uri: uri)],
      ),
    );
  }

  return ComposedRichText._(
    content: content,
    facets: facets.isEmpty ? null : facets,
  );
}

/// An http(s) scheme, in any case, followed by everything up to the next
/// whitespace, angle bracket or backtick
final _urlCandidate = RegExp(r'https?://[^\s<>`]+', caseSensitive: false);

/// Characters that, directly before a scheme, make it part of a longer word
final _wordCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);

/// The longest link URI the backend accepts once it has percent-encoded every
/// byte outside printable ASCII, mirroring its maxURILength
const _maxEncodedUriLength = 8192;

/// The UTF-16 span of the link within the candidate [start]..[end] of
/// [content] and the URI to emit for it, or null when the candidate is not a
/// link the backend would accept
({int start, int end, String uri})? _acceptedLink(
  String content,
  int start,
  int end,
) {
  if (!_startsAtWordBoundary(content, start)) {
    return null;
  }
  // Trailing punctuation is almost always sentence text, not part of the URL,
  // but a closing paren that balances the URL belongs to it (Foo_(bar)). The
  // URL is balanced when its depth is zero and it holds no `)` that closed
  // nothing; one scan finds both, and trimming a `)` only raises the depth.
  var depth = 0;
  var firstUnmatchedClose = end;
  for (var index = start; index < end; index++) {
    final unit = content.codeUnitAt(index);
    if (unit == _openParenthesis) {
      depth++;
    } else if (unit == _closeParenthesis) {
      depth--;
      if (depth < 0 && firstUnmatchedClose == end) {
        firstUnmatchedClose = index;
      }
    }
  }
  var trimmedEnd = end;
  while (trimmedEnd > start &&
      _trailingPunctuation.contains(content[trimmedEnd - 1])) {
    if (content.codeUnitAt(trimmedEnd - 1) == _closeParenthesis) {
      if (depth == 0 && firstUnmatchedClose >= trimmedEnd) {
        break;
      }
      depth++;
    }
    trimmedEnd--;
  }
  // The scheme is emitted lowercase; the rest of the URL stays as typed
  final typed = content.substring(start, trimmedEnd);
  final schemeEnd = typed.indexOf(':');
  final uri =
      typed.substring(0, schemeEnd).toLowerCase() + typed.substring(schemeEnd);
  if (!isAllowedWebUrl(uri) ||
      !_isPrintableAscii(_hostAndPortOf(uri)) ||
      _encodedLength(uri) > _maxEncodedUriLength) {
    return null;
  }
  return (start: start, end: trimmedEnd, uri: uri);
}

/// The host and port of the http(s) [uri]: its authority, which ends at the
/// first `/`, `?` or `#`, after the last `@`
///
/// The backend's encodeAuthority punycodes this part, and can reject the whole
/// post, only when it has a byte outside printable ASCII, so a URL is linked
/// only when this part is printable ASCII.
String _hostAndPortOf(String uri) {
  final authorityStart = uri.indexOf('://') + 3;
  final authorityEnd = uri.indexOf(RegExp('[/?#]'), authorityStart);
  final authority = uri.substring(
    authorityStart,
    authorityEnd == -1 ? uri.length : authorityEnd,
  );
  return authority.substring(authority.lastIndexOf('@') + 1);
}

/// Whether every character of [text] is printable ASCII (0x21..0x7E)
bool _isPrintableAscii(String text) =>
    text.codeUnits.every(_isPrintableAsciiUnit);

bool _isPrintableAsciiUnit(int unit) => unit >= 0x21 && unit <= 0x7E;

/// The length of [uri] after the backend percent-encodes each UTF-8 byte
/// outside printable ASCII into three characters
int _encodedLength(String uri) => utf8
    .encode(uri)
    .fold(0, (length, byte) => length + (_isPrintableAsciiUnit(byte) ? 1 : 3));

/// Characters trimmed from the end of a URL candidate
const _trailingPunctuation = {'.', ',', '!', '?', ';', ':', ')', '"', "'"};

const _openParenthesis = 0x28;
const _closeParenthesis = 0x29;

/// Whether the code point before [start] in [content], if any, is not a word
/// character
bool _startsAtWordBoundary(String content, int start) {
  if (start == 0) {
    return true;
  }
  // Step back over a whole surrogate pair so astral letters are seen whole
  var previousStart = start - 1;
  if (previousStart > 0 &&
      _isLowSurrogate(content.codeUnitAt(previousStart)) &&
      _isHighSurrogate(content.codeUnitAt(previousStart - 1))) {
    previousStart--;
  }
  return !_wordCharacter.hasMatch(content.substring(previousStart, start));
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
