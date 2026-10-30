# PRD: Formatting composer (mobile)

Status: draft, 2026-10-12. Owner: Bretton.

## Problem

Mobile users can't format what they write. The renderer already draws every facet feature in `social.coves.richtext.facet` (bold, italic, strikethrough, spoiler, inline code, blockquote, heading, code block), but the composers are plain `TextField`s. Only links and mentions become facets, and only at submit (`composeRichText` + `resolveMentions` in `lib/utils/rich_text_composer.dart`). Users see no styling of any kind until the post is up.

Mobile has no markdown and never will (2026-09-28 decision). Formatting has to come from a toolbar that writes facets directly, and the composer has to show the formatting as it's typed.

## Decisions (user, 2026-10-12)

1. **Surfaces:** create post (body field) and the reply screen, which writes every comment and reply. `lib/widgets/comment_composer.dart` is unused and gets deleted. Titles stay plain text.
2. **Formats:** the full lexicon set: bold, italic, strikethrough, spoiler, inline code, blockquote, heading, code block.
3. **Toolbar:** a bar above the keyboard while the body field is focused. A toggle applies to the selection, or, with a collapsed caret, to the text typed next.
4. **Live mentions and links:** text that matches the submit-time rules for `@handle`, `!community`, `!name@origin` and `https://` URLs is colored as it's typed. There are no lookups while typing. Resolution stays at submit, and a mention that doesn't resolve still posts as plain text.

## Editor approach

Build it on Flutter's own `EditableText`, with a custom `TextEditingController` (`FacetEditingController`) that keeps a sorted list of formatting ranges next to the text.

- **Why:** this keeps Flutter's own IME path, which is the one that got the Gboard selection fix in 3.47.2 (see the composer-shift memory). It also keeps the stock selection handles, spell-check, context menu and screen-reader support. The model already is the wire format: plain text plus ranges.
- **Rejected:**
  - **super_editor:** the stable release is two years old; open bugs with Japanese, Chinese and Korean input; screen readers fail while typing (#1072).
  - **flutter_quill:** breaks TalkBack and VoiceOver typing (#2531); autocorrect can't be configured; uses a Delta model.
  - **fleather:** uses a Delta model.
  - **appflowy_editor:** desktop-first, and licensed MPL/AGPL.
- **Inline styles:** `buildTextSpan` covers bold, italic, strikethrough, inline code (monospace), spoiler (dimmed background), heading font size, and mention/link color.
- **Block visuals:** quote bars and code-block backgrounds can't be drawn by a `TextSpan`. A painter behind the field draws them from the layout's line boxes (`getBoxesForSelection`; for empty lines, `getLocalRectForCaret`). Quoted text is marked by gutter bars, one per level, and is not indented.
- **No `WidgetSpan`s:** they would add characters to the stored text.
- **Fallback:** if chunk 01's device check shows ranges drifting under IME edits that the diff logic can't fix, stop the loop and re-plan on super_editor.

## Behavior

### Formatting model
- Each format is a set of ranges over the current text.
- **Inline formats** (bold, italic, strikethrough, spoiler, code):
  - Ranges may overlap across formats.
  - Ranges of the same format merge when they touch or overlap.
- **Block formats** (blockquote, heading, code block):
  - Always cover whole lines.
  - Toggling one applies to every line the selection touches.
  - Heading and code block are mutually exclusive on a line.
  - A blockquote may contain a heading or a code block. This is allowed by the lexicon.
- **Editing inside formatted text:**
  - Text typed inside a range extends it.
  - Text typed at a range's end extends it only if that format is armed at the caret. The caret arms the format of the text before it, as in other mobile editors.
  - Deleting text shrinks the ranges, and a range that becomes empty is removed.
  - Typing a newline inside a block splits the block.
  - A newline on an empty quoted or heading line ends the block.
  - A newline on an empty line that is the last line of a code block ends the code block on that line; empty lines elsewhere in a code block continue it, and a one-line empty code block is removed. When a quote wraps the code block, only the code block ends and the line stays quoted; a second newline on that empty quoted line ends the quote (user, 2026-10-28).
  - A newline at the start of a non-empty heading line inserts a plain empty line above; the heading stays with the text on the lower line, and a quote on the line covers both lines (user, 2026-10-28).
  - Backspace at the start of a line joins it into the line above, and the joined line takes the upper line's formats, so a quoted or heading line joined into a plain blank line loses its block format (user, 2026-10-28).
  - Dismissing the soft keyboard (Android Back, iOS interactive dismiss) unfocuses the field, so no caret remains (user, 2026-10-28). The keyboard closing while the app is in the background (switching apps) does not unfocus it.
  - Selecting text highlights only the selected characters on each line, not out to the widest line (user, 2026-10-28).
- **Keyboard edits** (autocorrect, swipe-typing, suggestions, paste, dictation):
  - These replace text in ways the controller sees only as an old value and a new value.
  - The controller diffs the two, uses the new caret position to break ties when characters repeat, and remaps every range.
  - While a composing region is active (Chinese/Japanese/Korean IME), remapping waits until composition commits.
- **No autocorrect** (user, 2026-10-28): the body field sets `autocorrect: false`, so pressing space never replaces the typed word. The suggestion strip and swipe-typing stay on; a suggestion is applied only when tapped.
- **Paste:** pasted text arrives unformatted.
- **Copy:** copies plain text.

### Toolbar
- **Contents:**
  - Inline buttons: Bold, Italic, Strikethrough, Spoiler, Code.
  - Block buttons: Quote, Heading, Code block.
  - On the reply screen, the bar also keeps the existing @, image and Send controls.
  - If the buttons don't fit the width, the row scrolls horizontally.
- **Button state:**
  - A button shows as active when its format covers the whole selection, or is armed at a collapsed caret.
  - Tapping an active button removes the format from the selection.
- **Heading** opens a level picker (H1–H3). The others toggle directly.
- **Disabled buttons:**
  - Inline buttons are disabled inside a code block, since code text isn't styled.
  - All formatting buttons are disabled once the facet budget is used up (see Submit).
- **Accessibility:** every button has a semantic label and a selected state.

### Live coloring
- Mentions and links are detected with the same rules `composeRichText` uses at submit, run synchronously on each change. They are colored with the renderer's palette (`lib/theme/rich_text_palette.dart`).
- Detection skips text inside inline code and code blocks. The submit path skips it too, so what's colored is what will link.

### Submit
1. **Trim.** Trimming the text shifts every range, and ranges that end up entirely inside trimmed whitespace are dropped. Comments are rejected (`InvalidFacets`) if facets arrive with untrimmed content.
2. **Convert to facets.** The controller turns its ranges into facets with UTF-8 byte offsets, using `Utf8Offsets`. Block ranges cover whole lines and exclude the trailing newline, as the lexicon requires. The backend doesn't check this.
3. **Merge link and mention facets.** Facets from `composeRichText` / `resolveMentions` are merged in as separate facets, sorted by `byteStart`. Formatting facets are counted first. Link and mention facets fill what remains of the 200-facet cap and are truncated as they are today.
4. **Spoiler and code block fields.** Spoiler is sent without a `reason` and code block without a `language`. Neither has an input field in this version.
5. **Optimistic copy.** The optimistic post or comment carries the same facets as the request.

### Loading existing facets (edit support)
Edit flows (comment edit, later post edit) are built elsewhere. This composer supplies the editor half, so an edit never drops facets. `comment.update` and `post.update` replace the whole record, so anything the client doesn't send is lost.

- **Hydration:** `FacetEditingController.fromRecord(content, facets)` converts UTF-8 byte offsets to UTF-16 with `Utf8Offsets`. It splits each facet into one range per feature, and widens block ranges to whole lines (the lexicon's reader rule). A range that doesn't sit on a character boundary is dropped.
- **Coverage:** all ten lexicon features load: bold, italic, strikethrough, spoiler, code, blockquote, heading, codeBlock, link, mention. Unknown `$type` features load too, as opaque ranges.
- **Attributes the UI can't set are preserved:** spoiler `reason`, codeBlock `language`, heading levels 4–6, blockquote levels above 1, and unknown features' data. These ranges remap like any other. Editing the text inside one keeps it, and it is removed only when all of its text is deleted. The heading picker shows a loaded H4–H6 as active, and picking H1–H3 replaces it.
- **Mentions and links are ranges in the model.** Loaded mention and link ranges remap with edits and keep their stored DID or `uri`. A mention or link range whose text is changed is dropped, and that text goes through detection again at submit. Untouched ones post as they are, with no mention lookup, and they count toward the facet budget ahead of newly detected ones. Live coloring covers loaded ranges and detected text alike.
- **Grouping:** at submit, features with exactly the same range are written as one facet, in lexicon union order. This saves room under the 200-facet cap.
- **Blocks nest by containment only.** The editor never produces a block range that crosses the edge of another block: the renderer drops those (`rich_text_renderer.dart`).
- **Round trip:** a record loaded and saved with no edits produces byte-identical content and facets. The exception is a block range that doesn't span whole lines (web or bridged records), which is widened on load.
- **Edit flow contract**, for the edit screen to follow: send the existing `embed`, `langs` and `labels` with the update. The optimistic copy replaces `content` and `facets` together, so old byte offsets are never applied to new text.

### Drafts
- The reply screen's in-memory drafts (`CommentsProvider`) store the text and the formatting ranges. Restoring a draft restores the formatting.
- Create post keeps its current behavior: state survives a tab switch through the `IndexedStack`, and the form resets after a successful post.
- Persisting drafts across app restarts is out of scope.

## Out of scope
- Markdown or any typed syntax shortcuts (`**`, `> `, `#`).
- A link button with custom link text. Links are only auto-detected.
- Spoiler reason and code-block language inputs.
- Nested blockquotes. The toolbar writes level 1, but loaded drafts keep their level.
- The edit screens themselves (menu entry, the `comment.update` / `post.update` calls). This PRD supplies the hydration and serialization they use (see Loading existing facets).
- Formatting-aware undo. System undo restores text, and ranges are remapped like any other edit, but formatting-only changes are not undoable.
- Type-ahead mention suggestions.
- Web composer changes.

## Constraints
- Flutter ≥ 3.47.2. The keyboard-input path must not regress the Gboard fix.
- **Physical-device check** (project rule for anything that touches keyboard layout): the Samsung with Gboard and an iPhone. The script covers:
  - typing with a format armed
  - swipe-typing
  - accepting a suggestion that replaces a half-formatted word
  - a misspelling followed by space stays as typed
  - dictation
  - Gboard Pinyin and iOS Japanese/Korean
  - emoji with zero-width joiners and flags inside bold
  - dragging selection handles across a block edge
  - TalkBack and VoiceOver reading the text and moving by character
- **Performance:** `buildTextSpan` plus the block painter must stay under 4 ms per keystroke on a 10,000-character post with 200 ranges, measured in profile mode.
- **Round trip:** loading the facets the editor produces and saving them again must give byte-identical facets, and every range must sit on a character boundary.

## Acceptance
- On create post and the reply screen, every lexicon format can be applied from the toolbar, shows live in the field, and posts as facets. Those facets render identically in `RichTextRenderer` and on the web.
- Typed mentions and links are colored as they're typed. Mentions resolve at submit exactly as they do now.
- A local-stack end-to-end run posts a formatted comment, and the record on the PDS carries the expected facets with trimmed content.
- `lib/widgets/comment_composer.dart` is deleted.

## Implementation notes

Built 2026-10-28/29 by /prd-loop on `prd/prd_composer_formatting` (base a76b4f8, PRD 283c62d). Not merged to main; the device and physical checks below are still open.

### Commits

- 01 Inline range model and selection toggles — 2ef1cab
- 02 Inline edit remapping and armed formats — b36f4c1
- 03 Composing gate, inline spans, IME device gate — f442694
- 03b Deferred IME fixes (autocorrect caret-format leak, mid-composition toggle) — fb0657a
- Harness: autocorrect off in the composer body field — 3714914
- 04 Block commands, invariants, empty-line activation — c946697
- 05 Block edit lifecycle, multiline edits, active state, code-block rules — d34ae3e
- 06 FacetTextField: block visuals, paste and copy — 262cde8
- Harness: Quote, Heading and Code block buttons in the IME harness — 42243a8
- Device-feedback fixes (code block exits on Enter, heading stays on split, unfocus on keyboard dismiss) — 68df38b
- 07 Live mention and link coloring — 2abd671
- 08 Submit serialization — 19412e4
- 09 Grouped block rendering, facet budget and over-cap handling — ba0f793
- 10 Formatting toolbar: seven toggles, state, accessibility — 4e6d159
- 11 Heading button and picker, budget-disabled toolbar — deffc62
- 12 fromRecord hydration and unchanged save — 6f9e1da
- 13 Loaded formatting under editing, H4–H6, budget share, other writers — 40bf8b0
- 14 Loaded mention and link ranges under editing — aba5e77
- 15 Reply screen adopts the composer; drafts keep ranges; comment_composer.dart deleted — df8c659
- 16 Create post adopts the composer — 9e913a4
- 17 Perf harness, local-stack E2E with web check, physical-device script — 8ea34b2

### Decisions

User decisions (2026-10-28; every open question took its recommended default unless noted):

- The composer body never autocorrects (`autocorrect: false`, suggestions stay on) on reply and create post.
- Enter: quote and code block continue onto the new line; heading does not. Enter at offset 0 of a non-empty heading line inserts a plain empty line above and the heading stays with the text (05-c). Enter on an empty last line of a code block ends the block; empty middle lines continue it. Multi-line paste follows the same per-newline rule (06-b(a)), so pasted code ending in a blank line exits the block, and pasting text with a blank line into a quote ends the quote there.
- Joins: Backspace joins and multi-line deletions take the upper line's full block formats; the lower line's blocks shrink to the lines they still cover. The literal rule is kept: joining a formatted line into a plain blank line above drops its quote/heading, and select-all + delete leaves line 0's blocks as zero-length ranges (`text = ''` drops them).
- Code block applied to lines drops their inline formatting (05-b). Paste is always unformatted, including Gboard clipboard-chip pastes, which follow typing rules (06-a).
- A link/mention with exactly the same range as a formatting facet joins it as one grouped facet (08-a).
- Over-cap (09-a option a): commands whose cost exceeds the remaining budget are disabled, removals stay enabled, edits are never blocked, submit is blocked while over 200 formatting facets.
- Heading picker has a "Normal text" entry; re-picking the active level also removes it (11-a).
- More than 20 features on one range split into facets of at most 20 over the same range (12-a).
- Records from other writers are canonicalized on save, never merging same-format ranges with differing attributes; content is trimmed (13-a option c).
- Comments get no optimistic copy; the served comment carrying the facets meets the requirement (15-a).
- Perf criterion is the maximum of the measured edits under 4 ms; percentiles are reported (17-a).
- Dismissing the keyboard unfocuses the field; selection highlight uses `BoxWidthStyle.tight`.

Orchestrator decisions (made during the build, flagged to the user, not yet confirmed):

- 04-a "expand" also applies to removals: a cut widens over a partly-cut inner block of the other format.
- The quote is always the outer block: a code block never strictly contains a quote; on equal spans the quote is outer (editor and renderer).
- Toolbar buttons are disabled and unselected when there is no valid selection (not focus-and-apply).
- A format toggled at a collapsed caret mid-composition applies to the whole composed insertion; a replacement inherits the formats of the first replaced character.
- 13-a canonicalization of records not written by this editor: adjacent same-level quotes merge; a quote crossing a code block widens to the code block's lines; raw JSON keys the typed model doesn't hold are dropped; exact duplicate unknown features collapse to one; a loaded inline range on a code-block line survives edits that don't touch that line. The picker shows an extra "Heading N" (4–6) entry only while every touched line has the same loaded level 4–6.
- A new same-format block (quote or code block) skips lines already held by a block of another level/language; loaded level and language are kept.
- A new code block splits at boundaries between quotes of different levels.
- Loaded link/DID policy filter: `fromRecord` drops a link failing `isAllowedWebUrl`, a mention failing `isValidDid`, and an unknown feature whose `$type` is the link/mention type id; that text goes through normal detection instead.
- Over-limit SnackBar copy, shared by reply and create post: "Too much formatting to send. Remove some and try again." (no PRD copy existed).
- **For the user:** typing right after a loaded mention or link (`@alice.test` → `@alice.testx`, `https://a.com` → `https://a.com/path`) keeps the loaded range over the original text. The alternative is to drop the range when a non-space character is appended at its end, so the extended token is re-detected at submit.

### Code map and invariants

- `lib/widgets/composer/facet_editing_controller.dart` — `FacetEditingController`. Constructors: default, `fromRecord(content, facets)` (hydration), `withRanges(text, {inlineRanges, blockRanges, featureRanges})` (drafts; no budget check). Both loaders canonicalize via `_canonicalizeLoadedRanges`/`_settled`. Loading unrelated content must go through these or `clear()`; a plain `text =` remaps and inherits the old first character's formats.
- Range types: `InlineRange` (format, start, end, `reason`), `BlockRange` (format, start, end, `level`, `language`), `FeatureRange` (mention/link/unknown feature, start, end). Getters return unmodifiable copies in current (display) coordinates; Dart `List.sort` is unstable, so any new sort needs an explicit tie-break.
- All edits go through the overridden `value` setter: inline remap (`_remapped`), block remap in line indexes (`_remappedBlocks`, then `_settled` on line-count changes), feature remap, and code-line inline stripping (`_outsideCodeBlocks`, only on touched lines). New range attributes must be carried through `_remapped`, `_merge`, `_subtract` and `_withBlockAdded`.
- Composing gate: during an IME composition stored ranges are held in pre-composition coordinates and shown through a provisional remap; commit remaps once; cancel restores the baseline. Toggles and `removeHeadings` call `_rebaseComposition` first. `clear()`/`text = ''` drop ranges, armed formats and composing toggles.
- Feature remap: mention/link ranges drop when an edit overlaps or lands strictly inside them, shift on insertion at start, stay on insertion at end. Unknown features use the opaque rule (inside insertion extends).
- Queries and commands: `toggleInline`, `toggleBlock(format, {level})`, `removeHeadings()`, `touchesHeading()`, `activeInlineFormats()` (armed set at a caret), `activeBlockFormats()`, `activeHeadingLevel()`, `isSelectionInCodeBlock()` (inline toggles are no-ops there), `pasteUnformatted(text)`.
- Budget: `formattingBudget`, `canToggleInline`/`canToggleBlock`, `toggleInlineCost`/`toggleBlockCost`; `FormattingBudget.of(...)` counts grouped and 20-feature-split facets the same way the serializer does. Toggles are no-ops when the `can*` check fails.
- `lib/widgets/composer/facet_serialization.dart` — `serializeFormatting(text, {inlineRanges, blockRanges, featureRanges})` returns trimmed content, UTF-8 byte facets grouped by identical range in lexicon union order, and `codeRanges`; throws `FacetLimitExceededException` above 200 formatting facets. Screens call it before any `await`/`setState`, then `composeFormattedRichText(content, formattingFacets:, excludedRanges: codeRanges)` (`lib/utils/rich_text_composer.dart`) and `resolveMentions`.
- `lib/widgets/composer/facet_text_field.dart` — `FacetTextField`: owns the decoration fill and paints code-block backgrounds and quote bars (fixed 28 px start gutter, mirrored in RTL; prefix widgets are rejected by a debug assert). Every paste route (keyboard, context menu, accessibility) goes through `pasteUnformatted`; `maxLength` counts graphemes and clamps pastes. Unfocuses when the bottom inset drops to 0 while resumed.
- `lib/widgets/composer/formatting_toolbar.dart` — `FormattingToolbar({controller, leading, trailing})`; buttons are non-focusable and sit in a `TextFieldTapRegion` so taps keep the field's focus and selection. New glyphs in `lib/widgets/icons/lucide_paths.dart` (bold and heading from lucide-static@1.64.0).
- Live coloring: `buildTextSpan` runs one detection per build, excluding code; colors from `lib/theme/rich_text_palette.dart`, shared with `RichTextRenderer`. The renderer resolves at most one quote plus one heading or code block per facet, quote outermost.
- Screens: `ReplyScreen` (toolbar with @/image leading and Send trailing while focused; drafts in `ComposerDraft` via `CommentsProvider.getDraft/saveDraft`) and `CreatePostScreen` (body `maxLength: 10000`, toolbar pinned above the keyboard while the body is focused). `lib/widgets/comment_composer.dart` is gone.
- Device tooling: `tool/composer_ime_harness.dart`, `integration_test/composer_keystroke_perf_test.dart` with `test_driver/composer_perf_driver.dart`, `.maestro/e10_formatted_comment.yaml`, and `docs/COMPOSER_PHYSICAL_DEVICE_SCRIPT.md`.

### Deferred findings

- Code-block background parity: editor uses `AppColors.insetSurface`, renderer `backgroundTertiary`. Open for the user.
- `ReplyScreen` doesn't pass `maxLength`, so reply pastes are unlimited.
- The 400 ms wall-time load perf test (chunk 13) may flake on slow machines.
- Paste clamp counts graphemes per side, so a grapheme formed across the selection join can be miscounted.
- `clear()` notify order during an active composition (codex suggestion, 16).
- Dart `trim()` strips U+FEFF but Go `TrimSpace` does not; content with a leading/trailing BOM could be rejected as InvalidFacets. Candidate for /file-issue.
- Floating or undocked keyboards report zero bottom inset, so the field may drop focus.
- The accessibility paste workaround (`_UnformattedPasteSelectionControls`, never-completing future) depends on Flutter 3.47.2 call order; recheck on upgrade.
- Field fill ignores focused/error border radii; hover tint is lost.
- `_outsideCodeBlocks` can leave `inlineRanges` unsorted (serializer output is sorted).
- Toggling a format off at a caret and then replacing forward re-arms it; an affinity-only caret change disarms.
- `toggleBlock` does not validate `level`; `InlineRange` has no asserts; `snapToGraphemeBoundaries` assumes start <= end.
- `_resetArmedFormats` guard and nested-map `_deepEquals` are untested; feature dedupe runs twice (F3).
- "No network on the detection path" is structural only, not asserted by a test.
- Remaining review suggestions per chunk are in the loop's `<NN-slug>/review-r*.md` reports (01: 7, 07: 7, 08: 8, 09: 10, 10: 9, 11: 11, 12: 12, 14: 11, 15: 9, 16: 7, 17: 12).

### Device and physical checks before merge to main

- 03 physical: run `tool/composer_ime_harness.dart` on the S26 (Gboard) and an iPhone through the PRD IME script plus mid-composition Bold; this is the go/no-go for staying on `TextField` versus super_editor. The user's 2026-10-28 harness session produced 68df38b, but the full script is not recorded as run.
- 06 physical: quote bars, code backgrounds and unformatted paste in the harness on the S26 and iPhone.
- 09 device (emulator): grouped [blockquote, heading] and [blockquote, codeBlock] facets render inside the quote; a duplicate block feature renders once.
- 11 physical (folded into 15/16): Heading picker opened with the keyboard up positions and dismisses correctly; budget-disabled buttons.
- 15 device (emulator): reply from post detail and from a comment — toolbar on focus only, live formats, draft keeps formatting, formatted reply posts and renders, over-limit SnackBar.
- 15 physical (S26 Gboard, iPhone): toolbar plus @/image/Send above the keyboard without overlap or jump on focus change; typing through suggestions, shift and selection handles while formatting; ranges survive draft reopen and post with correct facets. Script §3 row 11.
- 16 device (emulator): create post — toolbar above the keyboard while the body is focused, hidden when unfocused, body scrolls with the toolbar pinned, formatted post submits and renders, more than 200 facets shows the over-limit SnackBar.
- 16 physical (S26 Gboard, iPhone): toolbar pinned above the keyboard with no overlap or gap at SafeArea/home indicator, formatting while typing through suggestions, paste past 10,000 characters clamps with the caret correct, scroll a long body with the keyboard open and submit. Script §3.
- 17 device: `.maestro/e10_formatted_comment.yaml` on the emulator against the local stack (`a1_login_session` first; facets checked on the PDS at 3001), then the DoD 5 web check at localhost:8080. Script §2.
- 17 physical: S26 keystroke perf harness, pass at max < 4 ms in both series (script §1; reinstall Coves Dev afterwards), and the §3 keyboard and accessibility table on the S26 (Gboard) and an iPhone.
