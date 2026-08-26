import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Shared machinery for the source-scanning guards in `test/theme/`.
///
/// Those guards exist to stop a class of thing (a raw color, a font family)
/// from accreting outside the one file that owns it. They all need the same
/// unglamorous parts - find the package, walk it, and ignore what is inside a
/// comment - so those live here rather than being copied per guard and
/// drifting.

/// Source with comments separated out, line by line.
///
/// [code] and [comments] are parallel to the input and to each other: index
/// `i` of both describes input line `i`, so line numbers survive.
class StrippedSource {
  const StrippedSource(this.code, this.comments);

  /// Each line with its comments removed.
  final List<String> code;

  /// The comment text removed from each line; empty where there was none.
  final List<String> comments;
}

/// One line of scanned source, with everything a guard needs to judge it.
class SourceLine {
  SourceLine({
    required this.location,
    required this.index,
    required StrippedSource source,
  }) : _source = source;

  /// `<label>/<path relative to the scan root>:<1-based line number>`.
  final String location;

  /// 0-based position of this line within its file.
  final int index;

  final StrippedSource _source;

  /// This line with its comments removed.
  String get code => _source.code[index];

  /// The comment text this line carried.
  String get comment => _source.comments[index];

  /// The previous line's code; empty on a file's first line.
  String get previousCode => index > 0 ? _source.code[index - 1] : '';

  /// The previous line's comment; empty on a file's first line.
  String get previousComment => index > 0 ? _source.comments[index - 1] : '';

  /// The next line's code; empty on a file's last line.
  String get nextCode =>
      index + 1 < _source.code.length ? _source.code[index + 1] : '';

  /// This line's code plus up to [limit] - 1 lines after it.
  ///
  /// Lets a guard follow a value that `dart format` wrapped across lines
  /// rather than only seeing where it started.
  List<String> codeBlock(int limit) => [
    for (var i = index; i < _source.code.length && i < index + limit; i++)
      _source.code[i],
  ];

  /// Whether an `// ignore: <marker>` escape hatch covers this line.
  ///
  /// Deliberately narrow, because the obvious implementation is wrong in two
  /// ways. Matching the *raw* line lets the marker hatch from inside a string
  /// literal or doc-comment prose, and accepting any previous line that
  /// mentions it lets a trailing hatch on line N silently exempt line N+1 as
  /// well. So: the marker must sit in a real `//` comment (`///` doc prose
  /// does not count), either this line's own trailing comment, or a previous
  /// line that is nothing but that comment.
  bool isHatched(String marker) {
    final pattern = _hatchPattern(marker);
    if (pattern.hasMatch(comment)) {
      return true;
    }
    return previousCode.trim().isEmpty && pattern.hasMatch(previousComment);
  }
}

final _hatchPatterns = <String, RegExp>{};

RegExp _hatchPattern(String marker) => _hatchPatterns.putIfAbsent(
  marker,
  () => RegExp('//\\s*ignore:\\s*${RegExp.escape(marker)}\\b'),
);

/// Splits comments out of Dart source, preserving line count and numbering.
///
/// Guards match against source text, so a color or font family merely
/// *mentioned* in prose would otherwise read as a violation - and a guard
/// that cries wolf gets deleted. Two details that are easy to get wrong:
/// string literals are consumed whole, so a `//` inside a URL does not read
/// as the start of a comment; and block comments are counted rather than
/// flagged, because Dart's nest (`/* a /* b */ c */`) and a bool would treat
/// everything after the inner `*/` as code.
StrippedSource stripComments(List<String> lines) {
  final code = <String>[];
  final comments = <String>[];
  var blockDepth = 0;
  String? multiLineQuote;

  for (final line in lines) {
    final codeBuffer = StringBuffer();
    final commentBuffer = StringBuffer();
    var i = 0;

    while (i < line.length) {
      if (blockDepth > 0) {
        if (line.startsWith('/*', i)) {
          blockDepth++;
          commentBuffer.write('/*');
          i += 2;
          continue;
        }
        if (line.startsWith('*/', i)) {
          blockDepth--;
          commentBuffer.write('*/');
          i += 2;
          continue;
        }
        commentBuffer.write(line[i]);
        i++;
        continue;
      }

      if (multiLineQuote != null) {
        final end = line.indexOf(multiLineQuote, i);
        if (end == -1) {
          codeBuffer.write(line.substring(i));
          i = line.length;
        } else {
          codeBuffer.write(line.substring(i, end + multiLineQuote.length));
          i = end + multiLineQuote.length;
          multiLineQuote = null;
        }
        continue;
      }

      if (line.startsWith('//', i)) {
        commentBuffer.write(line.substring(i));
        break;
      }
      if (line.startsWith('/*', i)) {
        blockDepth = 1;
        commentBuffer.write('/*');
        i += 2;
        continue;
      }
      if (line.startsWith("'''", i) || line.startsWith('"""', i)) {
        multiLineQuote = line.substring(i, i + 3);
        codeBuffer.write(multiLineQuote);
        i += 3;
        continue;
      }

      final char = line[i];
      if (char == "'" || char == '"') {
        codeBuffer.write(char);
        i++;
        while (i < line.length) {
          final inner = line[i];
          if (inner == r'\') {
            final end = i + 2 > line.length ? line.length : i + 2;
            codeBuffer.write(line.substring(i, end));
            i = end;
            continue;
          }
          codeBuffer.write(inner);
          i++;
          if (inner == char) {
            break;
          }
        }
        continue;
      }

      codeBuffer.write(char);
      i++;
    }

    code.add(codeBuffer.toString());
    comments.add(commentBuffer.toString());
  }

  return StrippedSource(code, comments);
}

/// Absolute path of this source file, read off a live stack frame.
String _thisFile() {
  final frame = RegExp(
    r'(file:///.*?\.dart)',
  ).firstMatch(StackTrace.current.toString());
  if (frame == null) {
    fail('could not locate this helper from a stack trace');
  }
  return frame.group(1)!;
}

/// Resolves the package's `lib/` by walking up from this file to the nearest
/// `pubspec.yaml`, rather than from the process working directory, so guards
/// hold up however the suite is invoked.
///
/// (`Isolate.resolvePackageUri` would be the direct route but throws
/// `Unsupported operation` under the flutter_test VM.)
Directory resolveLibDir() {
  var dir = File.fromUri(Uri.parse(_thisFile())).parent;
  while (!File.fromUri(dir.uri.resolve('pubspec.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('walked to the filesystem root without finding pubspec.yaml');
    }
    dir = parent;
  }
  return Directory.fromUri(dir.uri.resolve('lib'));
}

/// Matches a `generated/` directory at any depth, as
/// `analysis_options.yaml`'s `**/generated/**` does - not just at the root.
final _generatedDir = RegExp('(^|/)generated/');

/// Generated sources, which no guard should judge.
///
/// Mirrors the `exclude:` list in `analysis_options.yaml:13-18`. Nothing
/// generated lives under `lib/` today, but a guard must not go wrong the day
/// something does.
bool isGenerated(String relativePath) =>
    _generatedDir.hasMatch(relativePath) ||
    relativePath.endsWith('.g.dart') ||
    relativePath.endsWith('.freezed.dart');

/// Every line of every `.dart` file under [root], recursively.
///
/// [isExempt] is consulted with each file's path relative to [root], always
/// with `/` separators whatever the platform uses. [scanned] collects the
/// files actually read, so a caller can tell an honestly clean tree apart
/// from a scan that found nothing to look at - the failure mode that would
/// make a guard pass forever.
List<SourceLine> readSourceLines(
  Directory root,
  String label, {
  bool Function(String relativePath)? isExempt,
  List<String>? scanned,
}) {
  final lines = <SourceLine>[];
  final prefixLength = root.path.length + 1;

  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final relativePath = file.path
        .substring(prefixLength)
        .replaceAll(Platform.pathSeparator, '/');
    if (isExempt != null && isExempt(relativePath)) {
      continue;
    }
    scanned?.add(relativePath);

    final source = stripComments(file.readAsLinesSync());
    for (var i = 0; i < source.code.length; i++) {
      lines.add(
        SourceLine(
          location: '$label/$relativePath:${i + 1}',
          index: i,
          source: source,
        ),
      );
    }
  }

  return lines;
}

/// Writes [files] into a fresh temp directory, deleted when the test ends.
///
/// Lets a guard run its real scanner over a tree built to contain one of
/// every case it claims to handle.
Directory createSourceTree(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('coves_source_scan');
  addTearDown(() => root.deleteSync(recursive: true));

  files.forEach((relativePath, contents) {
    File.fromUri(root.uri.resolve(relativePath))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
  });

  return root;
}
