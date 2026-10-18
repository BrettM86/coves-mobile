import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/moderation_constants.dart';
import '../../models/moderation_action.dart';
import '../../providers/viewer_authority_provider.dart';
import '../../services/api_exceptions.dart';
import '../../utils/moderation_copy.dart';

class ModerationSheetDecision {
  const ModerationSheetDecision({
    this.close = true,
    this.failureMessage,
    this.retryLocked = false,
  });

  final bool close;
  final String? failureMessage;
  final bool retryLocked;
}

/// Label of the preselected choice in a sheet whose reason is optional.
const String moderationNoReasonLabel = 'No reason';

class ModerationActionSheet<T> extends StatefulWidget {
  /// A sheet that cannot be confirmed until one of [reasons] is chosen.
  ModerationActionSheet({
    required this.title,
    required this.confirmLabel,
    required this.reasons,
    required this.failureMessage,
    required Future<T> Function(ModerationReason reason, String? privateNote)
    onSubmit,
    required this.authority,
    this.onResult,
    super.key,
  }) : reasonRequired = true,
       // The confirm button stays disabled until a reason is chosen.
       onSubmit = ((reason, privateNote) => onSubmit(reason!, privateNote));

  /// A sheet offering [reasons] after a preselected "No reason" choice; it
  /// can be confirmed with no reason, which submits null.
  const ModerationActionSheet.optionalReason({
    required this.title,
    required this.confirmLabel,
    required this.reasons,
    required this.failureMessage,
    required this.onSubmit,
    required this.authority,
    this.onResult,
    super.key,
  }) : reasonRequired = false;

  final String title;
  final String confirmLabel;
  final List<ModerationReason> reasons;
  final bool reasonRequired;
  final String failureMessage;
  final Future<T> Function(ModerationReason? reason, String? privateNote)
  onSubmit;
  final Future<ModerationSheetDecision> Function(T result)? onResult;

  /// The sheet belongs to the session open when it was shown: it closes
  /// with no message as soon as the session key changes, even while a
  /// submission is in flight, and ignores that submission's answer.
  final ViewerAuthorityProvider authority;

  static Future<R?> show<R>(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required List<ModerationReason> reasons,
    required String failureMessage,
    required Future<R> Function(ModerationReason reason, String? privateNote)
    onSubmit,
    required ViewerAuthorityProvider authority,
    Future<ModerationSheetDecision> Function(R result)? onResult,
  }) => _showSheet(
    context,
    ModerationActionSheet<R>(
      title: title,
      confirmLabel: confirmLabel,
      reasons: reasons,
      failureMessage: failureMessage,
      onSubmit: onSubmit,
      onResult: onResult,
      authority: authority,
    ),
  );

  /// Shows a sheet whose reason is optional; see
  /// [ModerationActionSheet.optionalReason].
  static Future<R?> showOptionalReason<R>(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required List<ModerationReason> reasons,
    required String failureMessage,
    required Future<R> Function(ModerationReason? reason, String? privateNote)
    onSubmit,
    required ViewerAuthorityProvider authority,
    Future<ModerationSheetDecision> Function(R result)? onResult,
  }) => _showSheet(
    context,
    ModerationActionSheet<R>.optionalReason(
      title: title,
      confirmLabel: confirmLabel,
      reasons: reasons,
      failureMessage: failureMessage,
      onSubmit: onSubmit,
      onResult: onResult,
      authority: authority,
    ),
  );

  static Future<R?> _showSheet<R>(
    BuildContext context,
    ModerationActionSheet<R> sheet,
  ) => showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => sheet,
  );

  @override
  State<ModerationActionSheet<T>> createState() =>
      _ModerationActionSheetState<T>();
}

class _ModerationActionSheetState<T> extends State<ModerationActionSheet<T>> {
  final TextEditingController _noteController = TextEditingController();
  final GlobalKey _primaryButtonKey = GlobalKey();
  ModerationReason? _reason;
  bool _submitting = false;
  String? _failureMessage;
  bool _retryLocked = false;
  late final Object? _sessionKey;
  bool _sessionEnded = false;

  @override
  void initState() {
    super.initState();
    _noteController.addListener(_onNoteChanged);
    _sessionKey = widget.authority.sessionKey;
    widget.authority.addListener(_onAuthorityChanged);
  }

  void _onNoteChanged() => setState(() {});

  void _onAuthorityChanged() {
    if (_sessionEnded || widget.authority.sessionKey == _sessionKey) {
      return;
    }
    _sessionEnded = true;
    // A sheet already closing has left the top of the stack; popping now
    // would close the route it was opened from instead.
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      // PopScope blocks only maybePop, so this closes a submitting sheet too.
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.authority.removeListener(_onAuthorityChanged);
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _reasonMissing || _noteTooLong) {
      return;
    }
    setState(() {
      _submitting = true;
      _failureMessage = null;
    });
    final note = _noteController.text;
    // Read before awaiting: the sheet can close while the request is out.
    final onSubmit = widget.onSubmit;
    final onResult = widget.onResult;
    late final T result;
    ModerationSheetDecision? decision;
    try {
      result = await onSubmit(_reason, note.trim().isEmpty ? null : note);
      // An answer for a session that has ended is not shown or applied.
      if (_sessionEnded) {
        return;
      }
      decision = await onResult?.call(result);
    } on Object catch (error, stackTrace) {
      // Catch everything so the sheet never stays locked behind canPop:
      // false, but report anything other than an API failure. The private
      // note is deliberately left out of the report.
      if (error is! ApiException) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'moderation action sheet',
            context: ErrorDescription('while submitting a moderation action'),
          ),
        );
      }
      if (mounted && !_sessionEnded) {
        setState(() {
          _failureMessage = widget.failureMessage;
          _retryLocked = false;
          _submitting = false;
        });
      }
      return;
    }
    if (!mounted || _sessionEnded) {
      return;
    }
    if (decision != null && !decision.close) {
      setState(() {
        _submitting = false;
        _failureMessage = decision!.failureMessage;
        _retryLocked = decision.retryLocked;
      });
      return;
    }
    setState(() => _submitting = false);
    // Let PopScope update its route entry before closing after a submission.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && !_sessionEnded) {
      _close(result);
    }
  }

  /// Closes the sheet itself. Marks the session ended first so a session
  /// change during the closing animation pops nothing more.
  void _close([T? result]) {
    _sessionEnded = true;
    Navigator.of(context).pop(result);
  }

  bool get _reasonMissing => widget.reasonRequired && _reason == null;

  bool get _noteTooLong =>
      _noteController.text.characters.length > privateNoteMaxGraphemes ||
      utf8.encode(_noteController.text).length > privateNoteMaxBytes;

  /// One radio per entry of [choices]; a null choice reads "No reason".
  Widget _reasonChoices<R extends ModerationReason?>(List<R> choices) {
    return RadioGroup<R>(
      groupValue: _reason as R?,
      onChanged: _submitting || _retryLocked
          ? (_) {}
          : (value) {
              setState(() => _reason = value);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final buttonContext = _primaryButtonKey.currentContext;
                if (buttonContext != null) {
                  Scrollable.ensureVisible(buttonContext);
                }
              });
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in choices)
            RadioListTile<R>(
              title: Text(
                choice == null
                    ? moderationNoReasonLabel
                    : moderationReasonLabel(choice)!,
              ),
              value: choice,
              enabled: !_submitting && !_retryLocked,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noteLength = _noteController.text.characters.length;
    final tooLong = _noteTooLong;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = math
        .max(0, 0.8 * (MediaQuery.sizeOf(context).height - keyboardInset))
        .toDouble();
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.reasonRequired)
          _reasonChoices<ModerationReason>(widget.reasons)
        else
          // Null is the "No reason" choice, selected while _reason is null.
          _reasonChoices<ModerationReason?>([null, ...widget.reasons]),
        TextField(
          controller: _noteController,
          enabled: !_submitting && !_retryLocked,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            labelText: 'Private note (optional)',
            errorText: tooLong ? 'Note is too long' : null,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text('$noteLength/$privateNoteMaxGraphemes'),
        ),
      ],
    );
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failureMessage != null) Text(_failureMessage!),
        const SizedBox(height: 12),
        FilledButton(
          key: _primaryButtonKey,
          onPressed: _reasonMissing || tooLong || _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_retryLocked ? 'Try again' : widget.confirmLabel),
        ),
      ],
    );
    return PopScope(
      canPop: !_submitting,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: sheetHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: math.min(48, sheetHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          constraints: BoxConstraints(
                            minWidth: 40,
                            maxWidth: 48,
                            maxHeight: math.min(48, sheetHeight),
                          ),
                          onPressed: _submitting ? null : _close,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [form, footer],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
