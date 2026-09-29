import 'dart:convert';

import 'package:coves_flutter/utils/utf8_offsets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const highSurrogate = 0xD800;
  const lowSurrogate = 0xDC00;

  // ASCII (1 byte), é (2), € (3), 👋 (4, a UTF-16 surrogate pair), an
  // unpaired high surrogate, an unpaired low surrogate, and an unpaired high
  // surrogate at the very end
  final text =
      'aé€👋${String.fromCharCode(highSurrogate)}b'
      '${String.fromCharCode(lowSurrogate)}z'
      '${String.fromCharCode(highSurrogate)}';

  /// UTF-16 indices that fall on code-point boundaries, including 0 and
  /// text.length (an unpaired surrogate is its own code point)
  List<int> codePointBoundaries(String value) {
    final boundaries = [0];
    var index = 0;
    for (final rune in value.runes) {
      index += rune > 0xFFFF ? 2 : 1;
      boundaries.add(index);
    }
    return boundaries;
  }

  int utf8PrefixLength(String value, int charIndex) =>
      utf8.encode(value.substring(0, charIndex)).length;

  group('Utf8Offsets.byteLength', () {
    test('equals the UTF-8 encoded length of the text', () {
      expect(Utf8Offsets(text).byteLength, utf8.encode(text).length);
      expect(Utf8Offsets(text).byteLength, 21);
    });

    test('counts an unpaired surrogate as three bytes', () {
      expect(Utf8Offsets(String.fromCharCode(highSurrogate)).byteLength, 3);
      expect(Utf8Offsets(String.fromCharCode(lowSurrogate)).byteLength, 3);
    });
  });

  group('Utf8Offsets.byteOffsetOf', () {
    test('matches the UTF-8 prefix length at every code-point boundary', () {
      final offsets = Utf8Offsets(text);
      for (final charIndex in codePointBoundaries(text)) {
        expect(
          offsets.byteOffsetOf(charIndex),
          utf8PrefixLength(text, charIndex),
          reason: 'charIndex $charIndex',
        );
      }
    });

    test('maps text.length to byteLength', () {
      expect(Utf8Offsets(text).byteOffsetOf(text.length), 21);
    });

    test('throws ArgumentError (not RangeError) for an index inside a '
        'surrogate pair', () {
      final insidePair = text.indexOf('👋') + 1;
      expect(
        () => Utf8Offsets(text).byteOffsetOf(insidePair),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error is RangeError,
            'is RangeError',
            isFalse,
          ),
        ),
      );
    });

    test('throws RangeError outside 0..text.length', () {
      final offsets = Utf8Offsets(text);
      expect(() => offsets.byteOffsetOf(-1), throwsRangeError);
      expect(() => offsets.byteOffsetOf(text.length + 1), throwsRangeError);
    });
  });

  group('Utf8Offsets.charIndexOf', () {
    test('inverts byteOffsetOf at every code-point boundary', () {
      final offsets = Utf8Offsets(text);
      for (final charIndex in codePointBoundaries(text)) {
        expect(
          offsets.charIndexOf(utf8PrefixLength(text, charIndex)),
          charIndex,
          reason: 'charIndex $charIndex',
        );
      }
    });

    test('maps byteLength to text.length', () {
      expect(Utf8Offsets(text).charIndexOf(21), text.length);
    });

    test('returns null for every offset inside a multi-byte sequence', () {
      final offsets = Utf8Offsets(text);
      final boundaryOffsets = {
        for (final charIndex in codePointBoundaries(text))
          utf8PrefixLength(text, charIndex),
      };
      final insideSequence = [
        for (var offset = 0; offset <= utf8.encode(text).length; offset++)
          if (!boundaryOffsets.contains(offset)) offset,
      ];
      // é: 1 inside offset, €: 2, 👋: 3, each unpaired surrogate: 2
      expect(insideSequence, hasLength(12));
      for (final offset in insideSequence) {
        expect(offsets.charIndexOf(offset), isNull, reason: 'offset $offset');
      }
    });

    test('returns null outside 0..byteLength', () {
      final offsets = Utf8Offsets(text);
      expect(offsets.charIndexOf(-1), isNull);
      expect(offsets.charIndexOf(22), isNull);
    });
  });

  group('Utf8Offsets on empty text', () {
    test('has zero length and maps offset 0 both ways', () {
      final offsets = Utf8Offsets('');
      expect(offsets.byteLength, 0);
      expect(offsets.byteOffsetOf(0), 0);
      expect(offsets.charIndexOf(0), 0);
    });
  });
}
