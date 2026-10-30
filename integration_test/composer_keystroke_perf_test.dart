// Profile-mode keystroke cost of the formatting composer on a 10,000
// character draft with 200 ranges (docs/PRD_COMPOSER_FORMATTING.md,
// Performance: buildTextSpan plus the block painter under 4 ms). Retype
// keystrokes carry a composing region, as Gboard's do, so the composing
// series times the provisional remap; deletes commit and form the committed
// series.
//
// Run on a physical device (profile mode does not run on simulators):
// flutter drive --driver=test_driver/composer_perf_driver.dart \
//   --target=integration_test/composer_keystroke_perf_test.dart \
//   --profile --flavor dev -d <device>
//
// No backend or sign-in is needed: the harness pumps a FacetTextField alone.
// Results: a `PERF SUMMARY` log line, and build/composer_keystroke_perf.json
// on the host written by the driver.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:coves_flutter/constants/app_colors.dart';
import 'package:coves_flutter/constants/app_theme.dart';
import 'package:coves_flutter/widgets/composer/facet_block_painter.dart';
import 'package:coves_flutter/widgets/composer/facet_editing_controller.dart';
import 'package:coves_flutter/widgets/composer/facet_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/widgets/composer/perf_fixture.dart';

const _warmUpEdits = 20;
const _measuredEdits = 200;

/// The pass criterion (open product question 17-a): the slowest measured
/// keystroke stays under this many milliseconds.
const _maxBudgetMs = 4.0;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'buildTextSpan plus the block painter stay under 4 ms per keystroke',
    (tester) async {
      final fixture = buildPerfFixture();
      final controller = FacetEditingController.withRanges(
        fixture.text,
        inlineRanges: fixture.inlineRanges,
        blockRanges: fixture.blockRanges,
        featureRanges: fixture.featureRanges,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_CreatePostBody(controller: controller));
      await tester.pumpAndSettle();

      // The production painters, as the field built them: the background
      // (fill and code backgrounds) and the foreground (quote bars).
      final paintFinder = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is FacetBlockPainter,
      );
      final customPaint = tester.widget<CustomPaint>(paintFinder);
      final painters = [customPaint.painter!, customPaint.foregroundPainter!];
      final paintBox = tester.renderObject<RenderCustomPaint>(paintFinder);
      final editableFinder = find.byType(EditableText);

      // The edit point: the plain word that starts at editOffset, next to
      // the quoted heading and quoted code block. Even edits delete its
      // first character with no composing region, which commits any active
      // composition; odd edits type it back the way Gboard does, with the
      // new character composing (offset to offset + 1, the word's start).
      // So every retype opens a composition and every delete commits it,
      // and the text returns to 10,000 characters (within the field's
      // maxLength) after each pair.
      final offset = fixture.editOffset;
      final typed = fixture.text[offset];
      final composingMicros = <int>[];
      final committedMicros = <int>[];
      final stopwatch = Stopwatch();

      for (var edit = 0; edit < _warmUpEdits + _measuredEdits; edit++) {
        final retype = edit.isOdd;
        final editable = tester.state<EditableTextState>(editableFinder);
        final text = controller.text;
        controller.value = retype
            ? TextEditingValue(
                text: text.replaceRange(offset, offset, typed),
                selection: TextSelection.collapsed(offset: offset + 1),
                composing: TextRange(start: offset, end: offset + 1),
              )
            : TextEditingValue(
                text: text.replaceRange(offset, offset + 1, ''),
                selection: TextSelection.collapsed(offset: offset),
              );

        // Timed before the pump, so the provisional caches are cold: the
        // value setter has just cleared _provisionalRanges,
        // _provisionalBlockRanges and _provisionalFeatureRanges, and its
        // listeners only schedule a rebuild and a repaint. On a retype this
        // call therefore runs the full provisional remap of all 200 ranges
        // and _outsideCodeBlocks, plus the composing split, as the first
        // build after a Gboard keystroke does.
        stopwatch
          ..reset()
          ..start();
        controller.buildTextSpan(
          context: editable.context,
          style: editable.widget.style,
          withComposing: true,
        );
        stopwatch.stop();
        final buildMicros = stopwatch.elapsedMicroseconds;

        await tester.pumpAndSettle();

        // The painters against the layout of the new text.
        final size = paintBox.size;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        stopwatch
          ..reset()
          ..start();
        for (final painter in painters) {
          painter.paint(canvas, size);
        }
        stopwatch.stop();
        recorder.endRecording().dispose();

        if (edit >= _warmUpEdits) {
          (retype ? composingMicros : committedMicros).add(
            buildMicros + stopwatch.elapsedMicroseconds,
          );
        }
      }

      // The last edit is a retype: commit its composition, untimed.
      controller.value = controller.value.copyWith(composing: TextRange.empty);
      await tester.pumpAndSettle();
      expect(controller.text, fixture.text);
      expect(controller.value.composing, TextRange.empty);
      final composing = _summarize(composingMicros);
      final committed = _summarize(committedMicros);
      debugPrint(
        'PERF SUMMARY composer keystroke '
        'composing: samples=${composing['samples']} '
        'max=${composing['max_ms']}ms p50=${composing['p50_ms']}ms '
        'p90=${composing['p90_ms']}ms p99=${composing['p99_ms']}ms | '
        'committed: samples=${committed['samples']} '
        'max=${committed['max_ms']}ms p50=${committed['p50_ms']}ms '
        'p90=${committed['p90_ms']}ms p99=${committed['p99_ms']}ms '
        'budget_max=${_maxBudgetMs}ms',
      );
      binding.reportData = <String, dynamic>{
        'composer_keystroke_perf': {
          'warm_up_edits': _warmUpEdits,
          'budget_max_ms': _maxBudgetMs,
          'composing': composing,
          'committed': committed,
        },
      };

      final maxMs =
          [...composingMicros, ...committedMicros].reduce(math.max) / 1000;
      expect(
        maxMs,
        lessThan(_maxBudgetMs),
        reason: 'the slowest keystroke must stay under $_maxBudgetMs ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Max and nearest-rank percentiles of [samplesMicros], in milliseconds.
Map<String, Object> _summarize(List<int> samplesMicros) {
  final sorted = [...samplesMicros]..sort();
  double percentileMs(int percentile) {
    final rank = math.max(1, (percentile / 100 * sorted.length).ceil());
    return sorted[rank - 1] / 1000;
  }

  return {
    'samples': sorted.length,
    'max_ms': sorted.last / 1000,
    'p50_ms': percentileMs(50),
    'p90_ms': percentileMs(90),
    'p99_ms': percentileMs(99),
    'samples_us': samplesMicros,
  };
}

/// The create-post body field as the screen builds it: the dark theme, the
/// page's 16 px scroll padding, and the body field's settings and
/// decoration (CreatePostScreen._inputDecoration).
class _CreatePostBody extends StatelessWidget {
  const _CreatePostBody({required this.controller});

  final FacetEditingController controller;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FacetTextField(
              controller: controller,
              minLines: 8,
              maxLength: 10000,
              autocorrect: false,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: 'What are your thoughts?',
                hintStyle: const TextStyle(color: AppColors.textPlaceholder),
                filled: true,
                fillColor: AppColors.backgroundTertiary,
                counterStyle: const TextStyle(color: AppColors.textSecondary),
                border: border(AppColors.inputBorder),
                enabledBorder: border(AppColors.inputBorder),
                focusedBorder: border(AppColors.primary, width: 2),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
