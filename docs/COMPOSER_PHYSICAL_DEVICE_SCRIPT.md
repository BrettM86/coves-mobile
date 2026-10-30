# Composer physical-device script

Device acceptance for docs/PRD_COMPOSER_FORMATTING.md (task 17): the keystroke perf run, the web rendering check, and the keyboard and accessibility items on the Samsung (Gboard) and an iPhone. Record each row as pass or fail with a note. Record the perf run and the web check as `device:` lines and the keyboard rows as `physical:` lines.

## 1. Keystroke perf harness (Samsung, profile mode)

1. Connect the phone with `/mobile-connect`. It runs wireless adb over Tailscale and prints the device id `100.93.73.61:<port>`. The harness needs no backend.
2. Run from the repo root:
   ```bash
   mise exec -- flutter drive \
     --driver=test_driver/composer_perf_driver.dart \
     --target=integration_test/composer_keystroke_perf_test.dart \
     --profile --flavor dev -d 100.93.73.61:<port>
   ```
3. Read the `PERF SUMMARY composer keystroke ...` line and `build/composer_keystroke_perf.json`. The driver writes the file even when the run fails. It holds two series, `composing` (retypes) and `committed` (deletes), each with max, p50, p90 and p99 in ms plus the raw samples in µs.
4. **Pass:** max < 4 ms across both series (200 measured edits, 100 each), after 20 warm-up edits. The test fails when max ≥ 4 ms.
5. The run installs the harness as Coves Dev (`social.coves.dev`). To restore the normal dev app, run `flutter build apk --flavor dev --profile --target-platform android-arm64` and then `adb install -r`.

Each sample times one call to `FacetEditingController.buildTextSpan(withComposing: true)`, made right after the value is set and before the frame so the provisional-range cache is cold, plus the field's own two `FacetBlockPainter`s (background and quote bars) painting into a `PictureRecorder` canvas after the frame, against the new layout. The draft is the 10,000-character fixture with 200 ranges, held in a create-post-sized `FacetTextField`. Edits alternate deleting and retyping one character at the fixture's edit offset. A retype sets a composing region over the typed character, as Gboard does, so it runs the provisional remap; a delete clears the composing region and commits.

## 2. Web rendering check (DoD 5)

Prerequisite: `.maestro/e10_formatted_comment.yaml` has passed. Its script logs `e10 comment <at-uri>` and `e10 reply root <at-uri>`.

1. Open the local web client (http://localhost:8080) with the browser tool and sign in as `mari.local.coves.dev`.
2. Open !science, search `NASA delays`, open the post and find the comment whose first line starts with the run's `E10 <timestamp>` stamp.
3. Check each of these over the same text the app shows:

| Check | Pass/fail |
|---|---|
| `bold` bold, `italic` italic, `struck` struck through | |
| `secret` concealed as a spoiler, revealed on click | |
| `snippet` in inline code style | |
| `@mari.local.coves.dev` rendered as a mention link | |
| `Quoted heading <tag>`: a heading inside a quote (quote + heading) | |
| `between the blocks`: plain, outside any quote | |
| `code line one <tag>` / `code line two`: one code block inside a quote (quote + code block) | |
| No leading or trailing blank space around the comment | |

4. Take a screenshot and record a `device:` line with the comment at-uri.

## 3. Keyboard and accessibility (Samsung with Gboard, iPhone)

Use the create-post body unless a row names the reply screen. Never post: discard the draft afterwards. Run every row on both phones and mark each cell pass or fail.

| # | Steps | Expected | Samsung | iPhone |
|---|---|---|---|---|
| 1 | Typing with a format armed: tap Bold, type `hello world`, tap Bold, type ` after`. | `hello world` bold, ` after` plain, caret never jumps. | | |
| 2 | Swipe-typing: tap Italic, swipe-type `keyboard` then `formatting` (iOS: QuickPath), tap Italic. | Both swiped words italic, with no duplicated or lost letters. | | |
| 3 | Suggestion replacing a half-formatted word: type `form`, select `fo`, tap Bold, put the caret at the end of `form`, accept the suggestion `formatting`. | The word is replaced once, with no duplicated or lost text and no crash. Note which part stays bold. | | |
| 4 | Misspelling then space: type `teh` then space. | `teh ` stays as typed (autocorrect is off in the composer). | | |
| 5 | Undoing an autocorrect: in the bold word `bold teh`, type space. The composer turns autocorrect off, so a correction should not happen. If the keyboard corrects anyway, press backspace once. | No correction happens. If one does, backspace undoes it or deletes the space, the bold range is unchanged, and there is no crash. | | |
| 6 | Dictation: tap Bold, dictate "testing dictation in bold", tap Bold. | All dictated words bold, no stray duplicates after dictation commits. | | |
| 7 | CJK IME: Gboard Pinyin on the Samsung, type `nihao` and pick 你好; iOS Japanese (`konnichiha` → こんにちは) and Korean (안녕). Do it once plain, once with Bold armed. | Composition underline shows while composing. The committed text is correct, and bold covers exactly the committed text. | | |
| 8 | Emoji inside bold: tap Bold, type `a👨‍👩‍👧b🇺🇸c`, tap Bold, then backspace through it. | Bold covers the whole run. Each backspace removes a whole family or flag, never half. | | |
| 9 | Selection handles across a block edge: make line 1 a quote and line 2 plain, long-press a word in line 1, drag the end handle into line 2, tap Quote. | The handles move smoothly across the edge, and the quote applies to both lines. Quote bars track the lines. | | |
| 10 | Screen reader: with TalkBack (Samsung) or VoiceOver (iPhone) on, focus the field holding a bold word, a quote and a code block, then read it and move by character through the formatted word. | The full text is read. Moving by character steps one character (one grapheme for emoji) at a time. | | |
| 11 | Reply screen, formatting row and focus: open a post, tap Comment, see the formatting row, then dismiss the keyboard (Back / swipe down). Tap the field again, then tap outside the field with the keyboard up. | The row shows while the field has focus and hides when focus is lost, with the keyboard up or down. The Send pill stays reachable. | | |
