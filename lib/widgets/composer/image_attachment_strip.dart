import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../constants/image_upload_limits.dart';
import '../../models/image_attachment.dart';
import '../../providers/image_attachments_controller.dart';
import '../../utils/alt_text_limits.dart';
import '../icons/lucide_icon_painter.dart';
import '../icons/lucide_paths.dart';

/// The composer's attached images as a horizontal strip of tiles with
/// remove, alt text, progress, error and Retry, and an add button.
///
/// Renders nothing while no image is attached. Tiles are drawn from the
/// picked local files and reorder by long-press drag; the add button stays
/// last. While [enabled] is false (a submit is running), Add, remove, alt
/// text, Retry and reordering do nothing.
class ImageAttachmentStrip extends StatelessWidget {
  const ImageAttachmentStrip({
    required this.controller,
    required this.onAdd,
    this.enabled = true,
    super.key,
  });

  static const double _tileSize = 96;
  static const double _gap = 8;

  final ImageAttachmentsController controller;
  final VoidCallback onAdd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final attachments = controller.attachments;
        if (attachments.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          key: const Key('image-attachment-strip'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _tileSize,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                proxyDecorator: _proxyDecorator,
                itemCount: attachments.length,
                // Gets the final index, the dragged tile already removed.
                // The list's screen reader move actions call this even
                // while the drag listeners are disabled.
                onReorderItem: (from, to) {
                  if (enabled) {
                    controller.reorder(from, to);
                  }
                },
                footer: controller.remaining > 0
                    ? _AddTile(size: _tileSize, onAdd: enabled ? onAdd : null)
                    : null,
                itemBuilder: (context, index) {
                  final attachment = attachments[index];
                  final isLast =
                      index == attachments.length - 1 &&
                      controller.remaining < 1;
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(attachment.id),
                    index: index,
                    enabled: enabled,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: isLast ? 0 : _gap,
                      ),
                      child: _AttachmentTile(
                        key: Key('image-attachment-tile-$index'),
                        attachment: attachment,
                        index: index,
                        count: attachments.length,
                        size: _tileSize,
                        onRemove: enabled
                            ? () => controller.remove(attachment.id)
                            : null,
                        onRetry: enabled
                            ? () => controller.retry(attachment.id)
                            : null,
                        onEditAlt: enabled
                            ? () => _editAlt(context, attachment, index)
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            for (var index = 0; index < attachments.length; index++)
              if (attachments[index].error case final error?
                  when attachments[index].status ==
                      ImageAttachmentStatus.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Image ${index + 1}: $error',
                    key: Key('image-attachment-error-$index'),
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 13,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  /// Opens the alt text editor for [attachment]; Save stores the text, and
  /// dismissing keeps the old alt.
  void _editAlt(BuildContext context, ImageAttachment attachment, int index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _AltTextEditor(
        initialAlt: attachment.alt,
        imageNumber: index + 1,
        onSave: (alt) => controller.setAlt(attachment.id, alt),
      ),
    );
  }

  static Widget _proxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Material(
        color: Colors.transparent,
        elevation: 6 * Curves.easeInOut.transform(animation.value),
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
      child: child,
    );
  }
}

/// Stops alt text input at its limits: an edit that would go over a limit
/// keeps only the longest grapheme prefix of its inserted run that fits,
/// with the caret after it.
///
/// An active IME composition is accepted as is, since handing the IME a
/// value that disagrees with its composing buffer desyncs it; the limit is
/// applied when the composition commits, clipping the composed run.
class _AltTextLimitFormatter extends TextInputFormatter {
  const _AltTextLimitFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid ||
        AltTextMeasure.of(newValue.text).isValid) {
      return newValue;
    }

    final oldCharacters = oldValue.text.characters.toList();
    final newCharacters = newValue.text.characters.toList();
    // The edit is the minimal grapheme diff: the common prefix and suffix,
    // bounded so they never overlap.
    final shorter = min(oldCharacters.length, newCharacters.length);
    var commonPrefix = 0;
    while (commonPrefix < shorter &&
        oldCharacters[commonPrefix] == newCharacters[commonPrefix]) {
      commonPrefix++;
    }
    var commonSuffix = 0;
    while (commonSuffix < shorter &&
        oldCharacters[oldCharacters.length - 1 - commonSuffix] ==
            newCharacters[newCharacters.length - 1 - commonSuffix]) {
      commonSuffix++;
    }
    var prefix = commonPrefix;
    var suffix = commonSuffix;
    // Where they overlap, the diff could sit anywhere in the overlap (typing
    // "a" into "aa"); it goes at the old selection, clamped into it.
    if (commonPrefix + commonSuffix > shorter) {
      final selection = oldValue.selection;
      final anchor = selection.isValid
          ? _graphemesBefore(oldCharacters, selection.start)
          : oldCharacters.length;
      prefix = max(shorter - commonSuffix, min(anchor, commonPrefix));
      suffix = shorter - prefix;
    }
    // A diff that touches the old composition widens to cover it, so a
    // committed composition counts as inserted even where its text is
    // unchanged. A diff clear of it leaves it, and the text between them,
    // as kept text.
    final composing = oldValue.composing;
    var widened = false;
    if (composing.isValid) {
      final compositionStart = _graphemesBefore(oldCharacters, composing.start);
      final compositionEnd =
          oldCharacters.length - _graphemesFrom(oldCharacters, composing.end);
      if (prefix <= compositionEnd &&
          oldCharacters.length - suffix >= compositionStart) {
        prefix = min(prefix, compositionStart);
        suffix = min(suffix, oldCharacters.length - compositionEnd);
        widened = true;
      }
    }
    final inserted = newCharacters.sublist(
      prefix,
      newCharacters.length - suffix,
    );
    final kept = _fit(
      newCharacters.sublist(0, prefix).join(),
      inserted,
      newCharacters.sublist(newCharacters.length - suffix).join(),
    );
    // The untouched text alone is over a limit, which only an accepted
    // composition leaves behind. Text already there is never dropped.
    if (kept == null) {
      // A deletion: accept it, it moves toward the limit.
      if (inserted.isEmpty) {
        return newValue;
      }
      return _dropInsertion(
        oldCharacters,
        newCharacters,
        prefix: prefix,
        suffix: suffix,
        // A composition the diff covers is the dropped run itself; only one
        // the edit left alone is still there to clip.
        untouchedComposing: widened ? TextRange.empty : composing,
      );
    }

    final head = newCharacters.sublist(0, prefix).join() + kept;
    final text =
        head + newCharacters.sublist(newCharacters.length - suffix).join();
    // An unchanged text keeps the old selection unless it splits a cluster.
    bool onBoundary(int offset) =>
        _graphemesBefore(oldCharacters, offset) +
            _graphemesFrom(oldCharacters, offset) ==
        oldCharacters.length;
    if (text == oldValue.text &&
        !composing.isValid &&
        onBoundary(oldValue.selection.start) &&
        onBoundary(oldValue.selection.end)) {
      return oldValue;
    }
    // Clipping can merge the graphemes around the cut; the caret goes to
    // the first boundary at or after it.
    var caret = 0;
    for (final character in text.characters) {
      if (caret >= head.length) {
        break;
      }
      caret += character.length;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  /// The edit with its inserted run dropped, for a field already over a
  /// limit. When an old composition the edit did not touch is still known,
  /// its overflow, never clipped while composing, is clipped now from its
  /// end; otherwise the field stays over the limit until Save clips it.
  static TextEditingValue _dropInsertion(
    List<String> oldCharacters,
    List<String> newCharacters, {
    required int prefix,
    required int suffix,
    required TextRange untouchedComposing,
  }) {
    final composing = untouchedComposing;
    final head = newCharacters.sublist(0, prefix);
    final tail = newCharacters.sublist(newCharacters.length - suffix);
    var characters = [...head, ...tail];
    var caret = head.length;

    if (composing.isValid) {
      // In old graphemes. The diff did not touch the composition (it would
      // have been widened over it), so it lies wholly before or after it.
      var start = _graphemesBefore(oldCharacters, composing.start);
      var end =
          oldCharacters.length - _graphemesFrom(oldCharacters, composing.end);
      final removed = oldCharacters.length - suffix - prefix;
      if (oldCharacters.length - suffix <= start) {
        start -= removed;
        end -= removed;
      }
      while (end > start && !AltTextMeasure.of(characters.join()).isValid) {
        characters = [
          ...characters.sublist(0, end - 1),
          ...characters.sublist(end),
        ];
        if (caret >= end) {
          caret--;
        }
        end--;
      }
    }

    final text = characters.join();
    // Dropping the run can merge the graphemes on either side of it; the
    // caret goes to the first boundary at or after the cut.
    final cut = characters.take(caret).join().length;
    var offset = 0;
    for (final character in text.characters) {
      if (offset >= cut) {
        break;
      }
      offset += character.length;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  /// How many of [characters] end at or before code-unit [offset].
  static int _graphemesBefore(List<String> characters, int offset) {
    var count = 0;
    var end = 0;
    for (final character in characters) {
      end += character.length;
      if (end > offset) {
        break;
      }
      count++;
    }
    return count;
  }

  /// How many of [characters] start at or after code-unit [offset].
  static int _graphemesFrom(List<String> characters, int offset) {
    var count = characters.length;
    var start = 0;
    for (final character in characters) {
      if (start >= offset) {
        break;
      }
      count--;
      start += character.length;
    }
    return count;
  }

  /// The longest prefix of [inserted] that keeps `head + kept + tail`
  /// within both limits, or null when `head + tail` alone is over one.
  static String? _fit(String head, List<String> inserted, String tail) {
    final base = AltTextMeasure.of(head + tail);
    if (!base.isValid) {
      return null;
    }
    var graphemes = base.graphemes;
    var bytes = base.bytes;
    var count = 0;
    while (count < inserted.length) {
      final characterBytes = utf8.encode(inserted[count]).length;
      if (graphemes + 1 > ImageUploadLimits.altTextMaxGraphemes ||
          bytes + characterBytes > ImageUploadLimits.altTextMaxBytes) {
        break;
      }
      graphemes++;
      bytes += characterBytes;
      count++;
    }
    // Graphemes can merge across the joins; shrink until the whole fits.
    while (count > 0 &&
        !AltTextMeasure.of(head + inserted.sublist(0, count).join() + tail)
            .isValid) {
      count--;
    }
    return inserted.sublist(0, count).join();
  }
}

class _AltTextEditor extends StatefulWidget {
  const _AltTextEditor({
    required this.initialAlt,
    required this.imageNumber,
    required this.onSave,
  });

  final String initialAlt;
  final int imageNumber;
  final ValueChanged<String> onSave;

  @override
  State<_AltTextEditor> createState() => _AltTextEditorState();
}

class _AltTextEditorState extends State<_AltTextEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialAlt,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    // Save can be pressed mid-composition, before the limit is applied.
    final value = _text.value;
    final text = const _AltTextLimitFormatter()
        .formatEditUpdate(value, value.copyWith(composing: TextRange.empty))
        .text;
    // Still over only when a composition's overflow outlived it unclipped;
    // the stored alt must fit, so the end gives way here as a last resort.
    widget.onSave(
      AltTextMeasure.of(text).isValid
          ? text
          : _AltTextLimitFormatter._fit('', text.characters.toList(), '')!,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keeps the field and Save above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        // Scrolls in a short viewport, such as landscape with the keyboard
        // up, so Save stays reachable.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Alt text for image ${widget.imageNumber}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _text,
                    builder: (context, value, _) {
                      final measure = AltTextMeasure.of(value.text);
                      if (!measure.showCounter) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '${measure.remaining}',
                        key: const Key('image-alt-editor-counter'),
                        style: TextStyle(
                          color: measure.remaining > 0
                              ? AppColors.textSecondary
                              : AppColors.error,
                          fontSize: 13,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('image-alt-editor-field'),
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [_AltTextLimitFormatter()],
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Describe this image',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  key: const Key('image-alt-editor-save'),
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.index,
    required this.count,
    required this.size,
    required this.onRemove,
    required this.onRetry,
    required this.onEditAlt,
    super.key,
  });

  final ImageAttachment attachment;
  final int index;
  final int count;
  final double size;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;
  final VoidCallback? onEditAlt;

  @override
  Widget build(BuildContext context) {
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final status = attachment.status;
    final hasAlt = attachment.trimmedAlt != null;

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              container: true,
              image: true,
              label: hasAlt
                  ? 'Image ${index + 1} of $count. Alt text set'
                  : 'Image ${index + 1} of $count',
              child: Image.file(
                attachment.file,
                cacheWidth: cacheWidth,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const ColoredBox(
                  color: AppColors.backgroundTertiary,
                  child: Center(
                    child: Icon(Icons.broken_image, color: AppColors.textMuted),
                  ),
                ),
              ),
            ),
            if (status == ImageAttachmentStatus.uploading)
              ColoredBox(
                color: AppColors.background.withValues(alpha: 0.5),
                child: Center(
                  child: SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(
                      // Indeterminate until the first progress event.
                      value: attachment.progress > 0
                          ? attachment.progress
                          : null,
                      strokeWidth: 3,
                      color: AppColors.textPrimary,
                      backgroundColor: AppColors.textPrimary.withValues(
                        alpha: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            if (status == ImageAttachmentStatus.failed)
              ColoredBox(
                color: AppColors.background.withValues(alpha: 0.6),
                child: Center(
                  child: TextButton.icon(
                    key: Key('image-attachment-retry-$index'),
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const LucideGlyph(
                      LucidePaths.rotateCcw,
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                    label: const Text('Retry'),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Semantics(
                button: true,
                enabled: onEditAlt != null,
                label: 'Alt text for image ${index + 1}',
                excludeSemantics: true,
                onTap: onEditAlt,
                child: GestureDetector(
                  key: Key('image-attachment-alt-$index'),
                  onTap: onEditAlt,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasAlt) ...[
                              LucideGlyph(
                                LucidePaths.check,
                                key: Key('image-attachment-alt-set-$index'),
                                size: 12,
                                color: AppColors.textPrimary,
                              ),
                              const SizedBox(width: 3),
                            ],
                            const Text(
                              'Alt',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                enabled: onRemove != null,
                label: 'Remove image ${index + 1}',
                excludeSemantics: true,
                onTap: onRemove,
                child: GestureDetector(
                  key: Key('image-attachment-remove-$index'),
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: LucideGlyph(
                          LucidePaths.x,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onAdd});

  final double size;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onAdd != null,
      label: 'Add image…',
      excludeSemantics: true,
      onTap: onAdd,
      child: Material(
        color: AppColors.backgroundTertiary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.inputBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('image-attachment-add'),
          onTap: onAdd,
          child: SizedBox.square(
            dimension: size,
            child: const Center(
              child: LucideGlyph(
                LucidePaths.imagePlus,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
