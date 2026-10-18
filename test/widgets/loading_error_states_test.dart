import 'dart:math' as math;

import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/providers/multi_feed_provider.dart';
import 'package:coves_flutter/widgets/feed_page.dart';
import 'package:coves_flutter/widgets/loading_error_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

class _ErrorStateCase {
  const _ErrorStateCase(this.name, this.label, this.widget);

  final String name;
  final String label;
  final Widget widget;
}

void main() {
  testWidgets(
    'full-screen error primary button labels are legible on their fill',
    (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      final cases = <_ErrorStateCase>[
        _ErrorStateCase(
          'NotFoundError',
          'Go Back',
          NotFoundError(
            title: 'Post not found',
            message: 'This post was removed.',
            onBackPressed: () {},
          ),
        ),
        _ErrorStateCase(
          'FullScreenError',
          'Retry',
          Scaffold(
            body: FullScreenError(message: 'Network error', onRetry: () {}),
          ),
        ),
        _ErrorStateCase(
          'FeedPage',
          'Retry',
          Scaffold(
            body: FeedPage(
              feedType: FeedType.discover,
              posts: const [],
              isLoading: false,
              isLoadingMore: false,
              hasMore: true,
              error: 'Network error',
              scrollController: scrollController,
              onRefresh: () async {},
              onRetry: () {},
              onClearErrorAndLoadMore: () {},
              isAuthenticated: false,
              currentTime: null,
              sessionStamp: null,
            ),
          ),
        ),
      ];

      final failures = <String>[];

      for (final c in cases) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(c.name),
            theme: AppTheme.dark,
            home: c.widget,
          ),
        );
        await tester.pumpAndSettle();

        final button = find.ancestor(
          of: find.text(c.label),
          matching: find.byType(ElevatedButton),
        );
        expect(button, findsOneWidget, reason: '${c.name} button');

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: button, matching: find.byType(RichText)),
        );
        final labelColor = paragraph.text.style?.color;
        expect(labelColor, isNotNull, reason: '${c.name} label colour');

        final material = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)).first,
        );
        final fillColor = material.color;
        expect(fillColor, isNotNull, reason: '${c.name} fill colour');

        final ratio = _contrastRatio(labelColor!, fillColor!);
        if (ratio < 4.5) {
          failures.add(
            '${c.name} "${c.label}" contrast ${ratio.toStringAsFixed(2)} '
            '< 4.5 (label $labelColor on fill $fillColor)',
          );
        }
      }

      expect(failures, isEmpty);
    },
  );
}
