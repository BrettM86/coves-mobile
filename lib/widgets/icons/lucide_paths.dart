import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_parsing/path_parsing.dart';

/// SVG path data for the Lucide icons used in the app.
///
/// Source: https://lucide.dev — ISC License, Copyright (c) Lucide Icons and
/// Contributors. The full license text ships at `assets/icons/lucide/LICENSE`
/// and is registered with Flutter's `LicenseRegistry` at startup.
///
/// Every icon is drawn in a 24x24 viewBox as a 2px stroke with round caps and
/// joins. Keep this file limited to raw `d` strings; rendering lives in
/// `LucideIconPainter`.
const String _heartD =
    'M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 '
    '22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 '
    '15c-1.5-1.5-3-3.2-3-5.5';
const String _pencilSparklesBody =
    'M21.174 6.813a2.82 2.82 0 0 0-3.986-3.987L3.842 16.175a2 2 0 0 0-.5.83 '
    'l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z';
const String _pencilA =
    'M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 '
    '4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z';
const String _messageSquareD =
    'M22 17a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 '
    '0 1 2 21.286V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2z';
const String _messageCircleD =
    'M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 '
    '1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719';
const String _thumbsDownD =
    'M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 '
    '2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22a3.13 '
    '3.13 0 0 1-3-3.88Z';
const String _eyeOffUpperD =
    'M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 '
    '10.747 10.747 0 0 1-1.444 2.49';
const String _eyeOffLowerD =
    'M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 '
    '10.75 10.75 0 0 1 4.446-5.143';
const String _eyeD =
    'M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 '
    '0 .696 10.75 10.75 0 0 1-19.876 0';

abstract final class LucidePaths {
  /// Declares the ISC license for the bundled Lucide glyphs (both the `d`
  /// strings here and the SVGs under `assets/icons/`) to Flutter's license
  /// registry. Call once during startup; the collector is lazy.
  static void registerLicense() {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(const [
        'Lucide Icons',
      ], await rootBundle.loadString('assets/icons/lucide/LICENSE'));
    });
  }

  /// `heart`
  static const List<String> heart = [_heartD];

  /// `info` — the sensitive-content banner's glyph
  ///
  /// The circle is drawn as two half arcs: the parser reads arc commands but
  /// has no `circle` primitive.
  static const List<String> info = [
    'M22 12a10 10 0 1 0-20 0a10 10 0 1 0 20 0',
    'M12 16v-4',
    'M12 8h.01',
  ];

  /// `arrow-left` — back button
  static const List<String> arrowLeft = ['m12 19-7-7 7-7', 'M19 12H5'];

  /// `download` — save image
  static const List<String> download = [
    'M12 15V3',
    'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4',
    'm7 10 5 5 5-5',
  ];

  /// `forward` — curved share/forward arrow
  static const List<String> forward = [
    'm15 17 5-5-5-5',
    'M4 18v-2a4 4 0 0 1 4-4h12',
  ];

  /// `message-circle` — reply bubble
  static const List<String> messageCircle = [_messageCircleD];

  /// `pencil` — compose/edit hint
  static const List<String> pencil = [_pencilA, 'm15 5 4 4'];

  /// `pencil-sparkles` — compose hint with flair
  static const List<String> pencilSparkles = [
    'M10 3H8',
    'm15.007 5.008 3.987 3.986',
    'M20 15v4',
    _pencilSparklesBody,
    'M22 17h-4',
    'M4 5v4',
    'M6 7H2',
    'M9 2v2',
  ];

  /// `message-square` — comment bubble
  static const List<String> messageSquare = [_messageSquareD];

  /// `thumbs-down` — downvote
  static const List<String> thumbsDown = [_thumbsDownD, 'M17 14V2'];

  /// `repeat-2` — repost
  static const List<String> repeat2 = [
    'm2 9 3-3 3 3',
    'M13 18H7a2 2 0 0 1-2-2V6',
    'm22 15-3 3-3-3',
    'M11 6h6a2 2 0 0 1 2 2v10',
  ];

  /// `ban` — a removal in the moderation log
  ///
  /// The circle is drawn as two half arcs, as in [info].
  static const List<String> ban = [
    'M22 12a10 10 0 1 0-20 0a10 10 0 1 0 20 0',
    'm4.9 4.9 14.2 14.2',
  ];

  /// `rotate-ccw` — a restore in the moderation log, and the Restore button
  static const List<String> rotateCcw = [
    'M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8',
    'M3 3v5h5',
  ];

  /// `eye-off` — an NSFW label in the moderation log
  static const List<String> eyeOff = [
    _eyeOffUpperD,
    'M14.084 14.158a3 3 0 0 1-4.242-4.242',
    _eyeOffLowerD,
    'm2 2 20 20',
  ];

  /// `eye` — a retracted NSFW label in the moderation log
  ///
  /// The pupil circle is drawn as two half arcs, as in [info].
  static const List<String> eye = [_eyeD, 'M15 12a3 3 0 1 0-6 0a3 3 0 1 0 6 0'];

  /// `lock` — admin-only moderation log content
  ///
  /// The body `rect` (x3 y11, 18x11, rx2) is written as a rounded-rectangle
  /// path: the parser has no `rect` primitive.
  static const List<String> lock = [
    'M5 11h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z',
    'M7 11V7a5 5 0 0 1 10 0v4',
  ];

  /// `chevron-down` — a control that opens a menu
  static const List<String> chevronDown = ['m6 9 6 6 6-6'];

  /// `chevron-right` — a row that opens another screen
  static const List<String> chevronRight = ['m9 18 6-6-6-6'];

  /// `check` — the selected entry of a menu
  static const List<String> check = ['M20 6 9 17l-5-5'];

  /// `x` — clears a filter
  static const List<String> x = ['M18 6 6 18', 'm6 6 12 12'];

  /// `gavel` — the moderation log entry on Explore
  static const List<String> gavel = [
    'm14.5 12.5-8 8a2.119 2.119 0 1 1-3-3l8-8',
    'm16 16 6-6',
    'm8 8 6-6',
    'm9 7 8 8',
    'm21 11-8-8',
  ];
}

/// Parses Lucide `d` strings into [ui.Path]s, cached per string.
ui.Path lucidePath(String d) => _cache.putIfAbsent(d, () {
  final proxy = _UiPathProxy();
  writeSvgPathDataToPath(d, proxy);
  return proxy.path;
});

final Map<String, ui.Path> _cache = {};

class _UiPathProxy extends PathProxy {
  final ui.Path path = ui.Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}
