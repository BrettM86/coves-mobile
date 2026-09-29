import 'dart:typed_data';

/// Maps between UTF-16 string indices and UTF-8 byte offsets of one text
///
/// atProto facet byte ranges count UTF-8 bytes, while Dart strings index
/// UTF-16 code units, so every facet read or written needs this translation.
/// Both tables are built in one pass at construction, making each lookup O(1).
/// Widths match what dart:convert's utf8 encoder emits, including 3 bytes for
/// an unpaired surrogate (encoded as U+FFFD).
class Utf8Offsets {
  factory Utf8Offsets(String text) {
    final length = text.length;
    // byteOffsets[i] is the byte offset of UTF-16 index i, or -1 when i falls
    // between the two halves of a surrogate pair
    final byteOffsets = Int32List(length + 1);
    var byteOffset = 0;
    var index = 0;
    while (index < length) {
      byteOffsets[index] = byteOffset;
      final codeUnit = text.codeUnitAt(index);
      if (codeUnit < 0x80) {
        byteOffset += 1;
      } else if (codeUnit < 0x800) {
        byteOffset += 2;
      } else if (_isHighSurrogate(codeUnit) &&
          index + 1 < length &&
          _isLowSurrogate(text.codeUnitAt(index + 1))) {
        byteOffsets[index + 1] = -1;
        byteOffset += 4;
        index += 2;
        continue;
      } else {
        byteOffset += 3;
      }
      index += 1;
    }
    byteOffsets[length] = byteOffset;

    // charIndices[b] is the UTF-16 index starting at byte b, or -1 when b
    // falls inside a multi-byte sequence
    final charIndices = Int32List(byteOffset + 1)..fillRange(0, byteOffset, -1);
    for (var charIndex = 0; charIndex <= length; charIndex++) {
      final offset = byteOffsets[charIndex];
      if (offset >= 0) {
        charIndices[offset] = charIndex;
      }
    }
    return Utf8Offsets._(byteOffsets, charIndices);
  }

  Utf8Offsets._(this._byteOffsets, this._charIndices);

  final Int32List _byteOffsets;
  final Int32List _charIndices;

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  /// The text's length in UTF-8 bytes
  int get byteLength => _byteOffsets.last;

  /// The UTF-8 byte offset of the UTF-16 [charIndex]
  ///
  /// Throws [RangeError] outside 0..text.length and [ArgumentError] for an
  /// index between the two halves of a surrogate pair.
  int byteOffsetOf(int charIndex) {
    RangeError.checkValueInInterval(
      charIndex,
      0,
      _byteOffsets.length - 1,
      'charIndex',
    );
    final offset = _byteOffsets[charIndex];
    if (offset < 0) {
      throw ArgumentError.value(
        charIndex,
        'charIndex',
        'falls inside a surrogate pair',
      );
    }
    return offset;
  }

  /// The UTF-16 index at the UTF-8 [byteOffset], or null when there is none
  ///
  /// Null when [byteOffset] is outside 0..byteLength or falls inside a
  /// multi-byte sequence.
  int? charIndexOf(int byteOffset) {
    if (byteOffset < 0 || byteOffset >= _charIndices.length) {
      return null;
    }
    final charIndex = _charIndices[byteOffset];
    return charIndex < 0 ? null : charIndex;
  }
}
