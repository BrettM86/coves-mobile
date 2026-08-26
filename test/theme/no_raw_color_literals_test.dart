import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/source_scan.dart';

/// Escape hatch. `// ignore: avoid_raw_color_literal` on the offending line,
/// or on a line of its own directly above it, suppresses that one hit.
///
/// Spelled like an analyzer suppression on purpose: nobody has to learn a
/// second convention, and the name follows lint-identifier style
/// (`avoid_print`, `avoid_relative_lib_imports`). It names no real lint, so
/// the analyzer ignores it - which would only change if the optional
/// `unnecessary_ignore` rule were ever switched on in
/// `analysis_options.yaml`.
const _hatch = 'avoid_raw_color_literal';

/// Raw color construction, in every spelling this SDK offers.
///
/// - `Color(0xFF…)` and its uppercase `0X` twin.
/// - `Color.fromARGB` / `fromRGBO` / `from` - the last being the wide-gamut
///   constructor, which takes named channel doubles and so carries no hex to
///   key on.
/// - `ColorSwatch(0x…` / `MaterialColor(0x…`, which are `Color` subclasses
///   that take the same literal.
///
/// `\bColor` will not match `backgroundColor(`. Every one of these has a
/// fixture in the self-check below, so a future edit to this pattern cannot
/// quietly drop one.
final _rawColor = RegExp(
  r'\b(?:Color|ColorSwatch|MaterialColor)\s*\(\s*0[xX]'
  r'|\bColor\.from[A-Za-z]*\s*\(',
);

/// A color constructor left open at end of line, and a hex literal opening
/// the next one - the shape `dart format` produces when the call is too long
/// to fit: `Color(\n  0xFF…,\n)`.
///
/// Checked as a specific pair rather than by matching [_rawColor] against the
/// two lines joined, which would flag every line that merely *precedes* a
/// color literal.
final _openColorCall = RegExp(
  r'\b(?:Color|ColorSwatch|MaterialColor)\s*\(\s*$',
);
final _leadingHex = RegExp(r'^\s*0[xX]');

bool _hasRawColor(SourceLine line) =>
    _rawColor.hasMatch(line.code) ||
    (_openColorCall.hasMatch(line.code) && _leadingHex.hasMatch(line.nextCode));

/// `lib/constants/` is the palette itself - the one place raw literals
/// belong.
bool _isExempt(String relativePath) =>
    relativePath.startsWith('constants/') || isGenerated(relativePath);

List<String> _violations(Directory root, {List<String>? scanned}) {
  return [
    for (final line in readSourceLines(
      root,
      'lib',
      isExempt: _isExempt,
      scanned: scanned,
    ))
      if (_hasRawColor(line) && !line.isHatched(_hatch)) line.location,
  ];
}

void main() {
  // GUARD A. This one is a plain `test`, not `testWidgets`: it reads source
  // files, builds no widgets and touches no fonts, so the google_fonts
  // fake-async constraint does not apply.
  //
  // Known blind spots, measured rather than assumed. Within this guard's
  // scope (`lib/` minus `lib/constants/`) there are 135 references to
  // Material's own color constants: `Colors.white` x48,
  // `Colors.transparent` x37, `Colors.red` x31, `Colors.black` x11,
  // `Colors.black45` x1, `Colors.green` x4, `Colors.grey` x3. `Colors.red`
  // is arguably the same defect as a raw hex literal, but folding 135 more
  // call sites into this pass is out of scope; widen the pattern once they
  // are migrated. Also unchecked: colors reached through a variable or
  // `Color.lerp`, and any literal a `// ignore:` hatch suppresses.
  test('lib/ has no raw color literals outside the palette', () {
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
          'Raw color literals belong in lib/constants/, so the palette stays '
          'the one place a color is defined.\n'
          'Fix: add a token to AppColors and reference it. If a literal '
          'genuinely is not a palette color, mark it `// ignore: $_hatch` on '
          'the line or on a line of its own directly above.\n\n'
          '${violations.join('\n')}\n',
    );
  });

  // The guard above can only report what its scanner sees, and `lib/` no
  // longer contains a raw literal to prove the scanner still works. Left
  // unproven, any part of it could break and the guard would quietly stay
  // green. So run the real scanner over a tree built to contain one of every
  // case - every spelling it must catch, and every case it must not.
  test('the scanner strips comments, honors the hatch, and skips exempt', () {
    final root = createSourceTree({
      'caught.dart': '''
const a = Color(0xFF00FF00);
const b = Color.fromARGB(255, 0, 0, 0);
const c = Color.fromRGBO(0, 0, 0, 1);
const d = Color.from(alpha: 1, red: 1, green: 0, blue: 0);
const e = Color(0XFF00FF00);
const f = ColorSwatch(0xFF00FF00, {});
const g = MaterialColor(0xFF00FF00, {});
const h = Color(
  0xFF00FF00,
);
''',
      'comments.dart': '''
/// Documented as Color(0xFF00FF00) in prose.
// const commentedOut = Color(0xFF00FF00);
/* const blockCommented = Color(0xFF00FF00); */
/* outer /* nested */ const stillComment = Color(0xFF00FF00); */
const url = 'https://example.com'; // not Color(0xFF00FF00)
''',
      'hatched.dart': '''
const sameLine = Color(0xFF00FF00); // ignore: $_hatch
const afterSameLine = Color(0xFF00FF00);
// ignore: $_hatch
const lineAbove = Color(0xFF00FF00);
const afterLineAbove = Color(0xFF00FF00);
const inString = 'ignore: $_hatch';
const afterString = Color(0xFF00FF00);
/// Doc prose mentioning ignore: $_hatch should not hatch.
const afterDocProse = Color(0xFF00FF00);
''',
      'constants/palette.dart': 'const p = Color(0xFF00FF00);\n',
      'generated/gen.dart': 'const g = Color(0xFF00FF00);\n',
      'nested/generated/gen.dart': 'const g = Color(0xFF00FF00);\n',
      'model.g.dart': 'const g = Color(0xFF00FF00);\n',
      'model.freezed.dart': 'const f = Color(0xFF00FF00);\n',
      'nested/deep/violation.dart': 'const n = Color(0xFF00FF00);\n',
      'clean.dart': 'const ok = AppColors.coral;\n',
    });

    final scanned = <String>[];
    final violations = _violations(root, scanned: scanned);

    expect(violations, [
      // Every spelling, including the wrapped one whose literal is on a
      // different line from its `Color(`.
      'lib/caught.dart:1',
      'lib/caught.dart:2',
      'lib/caught.dart:3',
      'lib/caught.dart:4',
      'lib/caught.dart:5',
      'lib/caught.dart:6',
      'lib/caught.dart:7',
      'lib/caught.dart:8',
      // A hatch covers ONE line. Each of these follows a hatched line and
      // must still be reported.
      'lib/hatched.dart:2',
      'lib/hatched.dart:5',
      'lib/hatched.dart:7',
      'lib/hatched.dart:9',
      // Proves the walk is recursive. `lib/` has exactly one top-level
      // file, so a scan that lost its recursion would still look clean.
      'lib/nested/deep/violation.dart:1',
    ]);
    // The exempt files must be skipped, not merely clean - and the scanner
    // must still have opened the files whose contents it cleared.
    expect(scanned, containsAll(['comments.dart', 'hatched.dart']));
    expect(
      scanned,
      isNot(
        anyElement(
          anyOf(
            contains('constants/'),
            contains('generated/'),
            endsWith('.g.dart'),
            endsWith('.freezed.dart'),
          ),
        ),
      ),
    );
  });
}
