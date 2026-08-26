import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/source_scan.dart';

/// Escape hatch, for a test that pumps an unthemed app on purpose.
const _hatch = 'avoid_bare_material_app';

/// A `MaterialApp(` or `MaterialApp.router(` construction.
final _materialApp = RegExp(r'\bMaterialApp(?:\.router)?\s*\(');

/// How far the argument list may run before the scan gives up.
const _maxArgLines = 40;

/// Files that already pump an unthemed app, frozen as of this commit.
///
/// 37 files, not the 31 a `MaterialApp(` grep reports: four more reach the
/// same unthemed default through `MaterialApp.router(`, and five arrived on
/// main with the provider/admin-panel refactor while this branch was in
/// flight. Those five are inherited debt, not new debt authored here.
///
/// This list may SHRINK and must never grow: it is harness debt, not a
/// design. Each entry renders in Material's stock light theme - Roboto,
/// `black87` - while production renders Inter on `0xFF0B0F14`, so whatever
/// they assert about layout or color is asserted about an app that does not
/// exist. Porting one to `pumpUnderAppTheme` is the fix; deleting its line
/// here is how you record that.
const _allowlist = {
  'router/post_route_test.dart',
  'screens/communities_see_all_screen_test.dart',
  'screens/create_post_screen_test.dart',
  'screens/main_shell_screen_test.dart',
  'screens/reply_screen_test.dart',
  'utils/pagination_scroll_listener_test.dart',
  'utils/url_launcher_test.dart',
  'widgets/animated_heart_icon_test.dart',
  'widgets/comment_card_avatar_test.dart',
  'widgets/comment_thread_test.dart',
  'widgets/community_avatar_fallback_icon_test.dart',
  'widgets/community_avatar_test.dart',
  'widgets/count_formatting_test.dart',
  'widgets/detailed_post_view_media_test.dart',
  'widgets/external_link_bar_test.dart',
  'widgets/feed_page_test.dart',
  'widgets/feed_screen_test.dart',
  'widgets/focused_thread_screen_test.dart',
  'widgets/fullscreen_video_player_test.dart',
  'widgets/media/favicon_test.dart',
  'widgets/media/native_image_embed_test.dart',
  'widgets/media/streamable_flow_test.dart',
  'widgets/media/streamable_video_embed_test.dart',
  'widgets/paginated_sliver_list_test.dart',
  'widgets/post_card_avatar_test.dart',
  'widgets/post_card_media_test.dart',
  'widgets/post_card_test.dart',
  'widgets/post_detail_loader_test.dart',
  'widgets/profile_header_test.dart',
  'widgets/rich_text_renderer_test.dart',
  'widgets/sign_in_dialog_test.dart',
  'widgets/user_avatar_test.dart',
  // Arrived on main with dae6851 (viewer-state hydration + admin panel
  // split). Same inherited debt as the rest of this list.
  'screens/communities_admin_panel_characterization_test.dart',
  'screens/communities_admin_panel_draft_persistence_test.dart',
  'screens/communities_admin_panel_inflight_test.dart',
  'screens/viewer_state_hydration_screens_test.dart',
  'widgets/post_detail_loader_hydration_test.dart',
};

/// The argument list opened at [start], followed across lines to its closing
/// bracket.
String _argsFrom(SourceLine line, int start) {
  final buffer = StringBuffer();
  var depth = 0;
  var offset = start;

  for (final text in line.codeBlock(_maxArgLines)) {
    for (var i = offset; i < text.length; i++) {
      final char = text[i];
      if (char == '(' || char == '[' || char == '{') {
        depth++;
      } else if (char == ')' || char == ']' || char == '}') {
        depth--;
        if (depth == 0) {
          return buffer.toString();
        }
      }
      buffer.write(char);
    }
    buffer.write(' ');
    offset = 0;
  }

  return buffer.toString();
}

/// This guard's own file.
///
/// Its synthetic fixtures are Dart source held in string literals, and the
/// scanner deliberately preserves string contents - so every `MaterialApp(`
/// it uses to TEST itself would otherwise be reported as a violation of
/// itself.
const _selfPath = 'theme/no_bare_material_app_test.dart';

List<String> _violations(Directory root, {List<String>? scanned}) {
  final violations = <String>[];

  for (final line in readSourceLines(
    root,
    'test',
    isExempt: (path) => path == _selfPath || isGenerated(path),
    scanned: scanned,
  )) {
    final match = _materialApp.firstMatch(line.code);
    if (match == null || line.isHatched(_hatch)) {
      continue;
    }
    // `match.end` sits just past the `(`, so the scan starts inside the
    // argument list with depth already counted from that bracket.
    final args = _argsFrom(line, match.end - 1);
    if (args.contains('theme:')) {
      continue;
    }
    final path = line.location.split(':').first.substring('test/'.length);
    if (_allowlist.contains(path)) {
      continue;
    }
    violations.add(line.location);
  }

  return violations;
}

void main() {
  // A plain `test`: it reads source files and builds no widgets.
  //
  // Freezes the harness debt the theme migration exposed. Most of this
  // suite pumps an app with no theme, so it measures Roboto on white while
  // production renders Inter on near-black - which is why an Inter-induced
  // overflow was invisible to 1476 passing tests. The existing offenders are
  // allowlisted by path; a new one fails here.
  //
  // This does not judge the allowlisted files, and it cannot tell a test
  // that is theme-independent on purpose from one that simply never thought
  // about it - that is what the hatch is for.
  test('no new test pumps an unthemed MaterialApp', () {
    final root = Directory.fromUri(resolveLibDir().parent.uri.resolve('test'));

    final scanned = <String>[];
    final violations = _violations(root, scanned: scanned);

    expect(
      scanned,
      containsAll(['widgets/post_card_test.dart', 'widget_test.dart']),
      reason: 'the scan never reached a known file - resolution is broken',
    );

    expect(
      violations,
      isEmpty,
      reason:
          'A test pumping MaterialApp without a `theme:` renders Material\'s '
          'stock light theme in Roboto, not the app. Layout and color '
          'assertions made there do not describe production.\n'
          'Fix: pump through `pumpUnderAppTheme`, or pass '
          '`theme: AppTheme.dark`. If the test is theme-independent on '
          'purpose, mark it `// ignore: $_hatch`.\n\n'
          '${violations.join('\n')}\n',
    );
  });

  test('the scanner reads the argument list, not just the line', () {
    final root = createSourceTree({
      'bare_test.dart': '''
void main() {
  pump(MaterialApp(home: Scaffold(body: Text('x'))));
  pump(MaterialApp.router(routerConfig: router));
  pump(MaterialApp(
    home: Scaffold(
      body: Text('wrapped across lines'),
    ),
  ));
}
''',
      'themed_test.dart': '''
void main() {
  pump(MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Text('x'))));
  pump(MaterialApp.router(theme: AppTheme.dark, routerConfig: router));
  pump(MaterialApp(
    home: Scaffold(body: Text('x')),
    theme: AppTheme.dark,
  ));
}
''',
      'hatched_test.dart': '''
void main() {
  pump(MaterialApp(home: Text('x'))); // ignore: $_hatch
  pump(MaterialApp(home: Text('x')));
}
''',
      'comments_test.dart': '''
// pump(MaterialApp(home: Text('x')));
/// Prose about MaterialApp(home: ...) with no theme.
''',
      'nested/deep/bare_test.dart': "pump(MaterialApp(home: Text('x')));\n",
    });

    final violations = _violations(root);

    expect(violations, [
      'test/bare_test.dart:2',
      'test/bare_test.dart:3',
      // The `theme:` of a themed app can sit several lines below its `(`,
      // and a bare one's arguments can too - so the whole argument list has
      // to be read, not the opening line.
      'test/bare_test.dart:4',
      // A hatch covers ONE line.
      'test/hatched_test.dart:3',
      'test/nested/deep/bare_test.dart:1',
    ]);
  });
}
