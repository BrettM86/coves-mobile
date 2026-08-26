import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/source_scan.dart';

/// The single file allowed to name a font.
const _typographyFile = 'constants/app_typography.dart';

/// Escape hatches, one per rule, each named for what it excuses. Accepted on
/// the offending line or on a line of its own directly above. See the note in
/// `no_raw_color_literals_test.dart` on why these are spelled like analyzer
/// suppressions.
const _googleFontsHatch = 'avoid_google_fonts_call';
const _familyHatch = 'avoid_font_family_literal';

/// Font families a widget may still name for itself.
///
/// A *value* allowlist rather than a list of exempt files, deliberately.
/// Code moves between files; the reason these are legitimate does not.
/// Monospace is a semantic choice - a DID, a hash, a code block - not a
/// brand choice, so it does not belong to the type scale.
const _allowedFamilies = {'monospace', 'Menlo', 'Courier New', 'Courier'};

/// A `fontFamily:` / `fontFamilyFallback:` argument. Requires the colon, so
/// prose like `[fontFamily]` and the declaration `fontFamily = 'Inter'` do
/// not match.
final _familyKey = RegExp(r'\bfontFamily(?:Fallback)?\s*:');

/// Single- or double-quoted string literal.
final _stringLiteral = RegExp('\'([^\']*)\'|"([^"]*)"');

/// A family read back from the typography file, e.g.
/// `fontFamily: AppTypography.fontFamily`. That is the pattern
/// `app_typography.dart` explicitly prescribes, so flagging it would have
/// the guard forbid its own recommended fix.
final _typographyReference = RegExp(r'\bAppTypography\.[A-Za-z_]\w*');

/// How far a wrapped argument may run before the scan gives up. Generous
/// enough for a formatted fallback list, bounded so a malformed file cannot
/// make the guard read to end of file.
const _maxValueLines = 12;

List<String> _literalsIn(String source) => [
  for (final match in _stringLiteral.allMatches(source))
    match.group(1) ?? match.group(2)!,
];

/// The argument value starting at [start] on [line], followed across lines
/// until the comma or closing bracket that ends it.
///
/// Bounding at the separator matters: scanning to end of line instead would
/// let `fontFamily: brandVariable, fontFamilyFallback: const ['Menlo']` pass,
/// because the allowed literal later on the line would answer for the
/// unresolved one - defeating the guard on exactly the input it exists to
/// catch. Following past end of line matters for the same reason in the
/// other direction: `dart format` wraps a long fallback list, and a
/// single-line read would see an empty value and report nothing useful.
///
/// Bracket depth is tracked naively, so a bracket inside a string literal
/// would confuse it. Font family names do not contain brackets.
String _valueAfter(SourceLine line, int start) {
  final buffer = StringBuffer();
  var depth = 0;
  var offset = start;

  for (final text in line.codeBlock(_maxValueLines)) {
    for (var i = offset; i < text.length; i++) {
      final char = text[i];
      if (char == '(' || char == '[' || char == '{') {
        depth++;
      } else if (char == ')' || char == ']' || char == '}') {
        if (depth == 0) {
          return buffer.toString();
        }
        depth--;
      } else if (char == ',' && depth == 0) {
        return buffer.toString();
      }
      buffer.write(char);
    }
    buffer.write(' ');
    offset = 0;
  }

  return buffer.toString();
}

bool _isExempt(String relativePath) =>
    relativePath == _typographyFile || isGenerated(relativePath);

List<String> _violations(Directory root, {List<String>? scanned}) {
  final violations = <String>[];

  for (final line in readSourceLines(
    root,
    'lib',
    isExempt: _isExempt,
    scanned: scanned,
  )) {
    // Rule 1: the family is chosen by the *method name* at a GoogleFonts
    // call site, so every such site is a place the font is decided.
    if (line.code.contains('GoogleFonts.') &&
        !line.isHatched(_googleFontsHatch)) {
      violations.add('${line.location}  (GoogleFonts call)');
      continue;
    }

    // Rule 2: naming a family directly, unless it is one of the allowed
    // monospace families or a reference back to the typography file.
    final key = _familyKey.firstMatch(line.code);
    if (key == null || line.isHatched(_familyHatch)) {
      continue;
    }

    // Every literal in the value, not a match on one exact shape: the value
    // may be a conditional (`isMono ? 'monospace' : null`) or a list
    // (`const ['Menlo', 'Courier New']`), and a shape-matching regex would
    // call both of those violations.
    final value = _valueAfter(line, key.end);
    final families = _literalsIn(value);
    final disallowed =
        families.where((family) => !_allowedFamilies.contains(family)).toList();

    if (disallowed.isNotEmpty) {
      violations.add(
        '${line.location}  (font family: ${disallowed.join(', ')})',
      );
    } else if (families.isEmpty && !_typographyReference.hasMatch(value)) {
      // A family that is neither a literal nor an AppTypography lookup came
      // from somewhere this scanner cannot see, which is exactly the
      // accretion the guard exists to stop.
      violations.add('${line.location}  (unresolved font family)');
    }
  }

  return violations;
}

void main() {
  // GUARD B, the companion to guard A. A plain `test`: it reads source
  // files, builds no widgets and touches no fonts.
  //
  // Known blind spots: a family reached through a variable that this
  // scanner cannot follow to its definition, `TextStyle` copies that
  // inherit a family, and anything a hatch suppresses. The point is not to
  // make naming a font impossible - it is to make it happen in one file, so
  // that changing the app's font stays a one-line change.
  test('lib/ names a font only in app_typography.dart', () {
    final scanned = <String>[];
    final violations = _violations(resolveLibDir(), scanned: scanned);

    // A guard that silently scanned nothing would pass forever. Anchor on
    // files that must exist rather than on a count, which would rot - and
    // on a NESTED one, because `lib/` has exactly one top-level file and a
    // scan that lost its recursion would still find that one.
    expect(
      scanned,
      containsAll(['main.dart', 'widgets/rich_text_renderer.dart']),
      reason: 'the scan never reached a known file - resolution is broken',
    );

    expect(
      violations,
      isEmpty,
      reason:
          'Only lib/$_typographyFile may name a font family, so switching '
          'the app font stays a one-line change.\n'
          'Fix: read the family from the theme (an unstyled Text already '
          'inherits it), or from an AppTypography accessor. Monospace is '
          'allowed inline: ${_allowedFamilies.join(', ')}.\n'
          'If a site is a genuine exception, mark it '
          '`// ignore: $_googleFontsHatch` or `// ignore: $_familyHatch` on '
          'the line or on a line of its own directly above.\n\n'
          '${violations.join('\n')}\n',
    );
  });

  // Guard B's rules are mostly about what it must NOT flag, and once the
  // migration lands `lib/` will contain no example of any of them. Run the
  // real scanner over a tree that does.
  test('the scanner allows monospace, catches families, honors hatches', () {
    final root = createSourceTree({
      'caught.dart': '''
final a = GoogleFonts.nunito(fontSize: 13);
const b = TextStyle(fontFamily: 'Nunito');
const c = TextStyle(fontFamily: someVariable);
const d = TextStyle(fontFamily: brandVariable, fontFamilyFallback: ['Menlo']);
const e = TextStyle(
  fontFamilyFallback: [
    'Menlo',
    'Nunito',
  ],
);
''',
      'allowed.dart': '''
const mono = TextStyle(fontFamily: 'monospace');
const conditional = TextStyle(fontFamily: isMono ? 'monospace' : null);
const fallback = TextStyle(
  fontFamilyFallback: const ['Menlo', 'Courier New', 'Courier'],
);
const wrapped = TextStyle(
  fontFamily:
      'monospace',
);
const wrappedList = TextStyle(
  fontFamilyFallback: const [
    'Menlo',
    'Courier New',
  ],
);
const wrappedConditional = TextStyle(
  fontFamily: isMono
      ? 'monospace'
      : null,
);
const resolved = TextStyle(fontFamily: AppTypography.fontFamily);
''',
      'comments.dart': '''
/// Prose mentioning GoogleFonts.nunito and fontFamily: 'Nunito'.
// final commentedOut = GoogleFonts.nunito();
/* const blockCommented = TextStyle(fontFamily: 'Nunito'); */
''',
      'hatched.dart': '''
final a = GoogleFonts.nunito(); // ignore: $_googleFontsHatch
final b = GoogleFonts.nunito();
// ignore: $_familyHatch
const c = TextStyle(fontFamily: 'Nunito');
const d = TextStyle(fontFamily: 'Nunito');
''',
      _typographyFile: '''
final theme = GoogleFonts.interTextTheme();
const family = TextStyle(fontFamily: 'Inter');
''',
      'model.g.dart': 'final g = GoogleFonts.nunito();\n',
      'nested/generated/gen.dart': 'final g = GoogleFonts.nunito();\n',
      'nested/deep/violation.dart': 'final n = GoogleFonts.nunito();\n',
      'clean.dart': 'const ok = TextStyle(fontSize: 13);\n',
    });

    final scanned = <String>[];
    final violations = _violations(root, scanned: scanned);

    expect(violations, [
      'lib/caught.dart:1  (GoogleFonts call)',
      'lib/caught.dart:2  (font family: Nunito)',
      'lib/caught.dart:3  (unresolved font family)',
      // The allowed 'Menlo' later on the line must not answer for the
      // unresolved family before it.
      'lib/caught.dart:4  (unresolved font family)',
      // A fallback list `dart format` wrapped across four lines.
      'lib/caught.dart:6  (font family: Nunito)',
      // A hatch covers ONE line; both of these follow a hatched line.
      'lib/hatched.dart:2  (GoogleFonts call)',
      'lib/hatched.dart:5  (font family: Nunito)',
      // Proves the walk is recursive.
      'lib/nested/deep/violation.dart:1  (GoogleFonts call)',
    ]);
    expect(scanned, containsAll(['allowed.dart', 'comments.dart']));
    expect(scanned, isNot(contains(_typographyFile)));
    expect(scanned, isNot(contains('model.g.dart')));
    expect(scanned, isNot(contains('nested/generated/gen.dart')));
  });
}
