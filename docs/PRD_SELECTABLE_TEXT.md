# PRD: Selectable text (mobile)

Status: decisions made 2026-11-12, ready to chunk.

## Problem

Users can't copy what other people wrote. The only selectable text in the app is the parent post or comment in the reply composer (shipped in `49c042d`). Everywhere else, long-pressing a post or comment does nothing useful, or collapses the comment.

That first change also showed two problems that apply everywhere:

1. Copying across a heading, quote, code block or image loses the line breaks between them ("HeadingBody"). `RichTextRenderer` draws each block as its own widget, and Flutter's default `SelectionArea` joins separate widgets with no separator. Paragraphs between blocks share one widget and keep their breaks.
2. Hidden spoilers must never reach the clipboard. This is fixed: unrevealed spoilers render placeholder text (`49c042d`). Every new surface inherits it as long as it renders through `RichTextRenderer`.

## Goal

Where someone is reading full content, long-press selects text and offers Copy, and the copied text keeps its block structure. Where text is a preview you tap to open, behaviour stays as it is.

## Surfaces

### Make selectable

| Surface | Where | Renders via | Notes |
|---|---|---|---|
| Post detail: title and body | `lib/widgets/detailed_post_view.dart` (title ~:316, body `_buildBodyText` ~:714) | title `Text`, body `RichTextRenderer` | One region from title to body. The sensitive-content banner and media section (gallery, embed `PageView` ~:505) sit between them and go under `SelectionContainer.disabled`. Author row and action bar stay outside. |
| Profile bio | `lib/widgets/profile_header.dart` ~:398 | `Text` | The DID row keeps tap-to-copy. |
| Community About description | `lib/screens/community/community_feed_screen.dart` `_buildAboutSection` ~:1141, text ~:1169 | `Text` | Only the full About tab, not the 2-line header. |
| Image alt text in the lightbox | `lib/widgets/image_viewer.dart` `_buildAltText` ~:849 | `Text` | Sits outside the zoom and paging gestures. |
| Reply composer preview | `lib/screens/compose/reply_screen.dart:862` | shipped | Its `SelectionArea` wraps the whole `PostCard` / `CommentThread`, so author names, handles and timestamps are selectable today. Exclude that metadata (decision 4) and give the region the same separator delegate. Copy picks up only the post title and body, or the comment bodies (user, 2026-11-18). |
| Comment "Select text" sheet | `lib/widgets/comment_card.dart` "⋯" menu (`_buildCommentMenu` ~:857) | new bottom sheet, body via `RichTextRenderer` | Menu item `Select text` on a comment with text opens a bottom sheet showing that comment's body, selectable (decision 3). Not offered on deleted or removed comments or comments with no text. |

### Leave as they are

Comments on post detail and focused thread keep long-press-to-collapse. Users copy a comment from its "Select text" menu item or by replying to it, where the composer preview is selectable (decision 1).

The rest are tap-to-open previews: feed `PostCard`s, notification rows, modlog entries, community tiles and hero cards, `CompactPostCard`, the Bluesky embed card, and link embed titles. Selection there would fight tap-to-navigate and the horizontal feed `PageView`. Users open the item and copy from the detail view. Feed posts have no copy menu action (decision 3).

The community guidelines screen is static app text, not user content. It is out of scope unless you want it (`flutter_markdown_plus` has a `selectable:` flag).

## Behaviour

1. Long-press on a selectable surface selects the word and shows the platform toolbar, which includes Copy and Select all (iOS may add system items such as Look Up and Share). Dragging handles extends the selection.
2. Select all selects only within that surface's region (one post title and body, one bio), not the whole screen.
3. Copied text has a single `\n` between adjacent selected blocks, and only between two blocks that both have selected content: paragraph, heading, quote (including nested quotes), code block, and the post title. A partial selection has no leading or trailing newline. Newlines inside one block (paragraph gaps, code lines) are kept as written.
4. Image placements contribute no text in any state, including the loading and error fallbacks (`ImageLoadError` shows "Image removed").
5. The code block language label is not copied.
6. Unrevealed spoilers copy as placeholder text. Revealed spoilers copy as their real text.
7. Taps keep working inside a selectable region: links, mentions, spoiler reveal, image taps, and opening the lightbox. Horizontal swipes on a media carousel inside the post region still page and do not start a selection.
8. Tapping outside the region clears the selection, and the tapped control still does its own action. Starting to scroll the page does not select text.
9. VoiceOver and TalkBack behaviour is unchanged, apart from the new selection actions the platform adds.
10. A comment's "⋯" menu offers `Select text` when the comment has text and is not deleted or removed. It opens a bottom sheet holding only that comment's body as one selectable region (no author, handle, timestamp, gallery images or votes; images placed inside the comment's text are shown, and copy leaves them out). Hidden spoilers in the sheet start hidden regardless of their state in the thread. Dismissing the sheet (tap outside it, drag it down, or back) returns to the thread unchanged.

## Design notes

- The line-break fix lives in `RichTextRenderer`, so every surface gets it. It needs a custom `SelectionContainerDelegate` (subclassing `MultiSelectableSelectionContainerDelegate`), or another mechanism, that inserts a newline between block selectables when it builds the copied text. Flutter 3.47.2 (pinned in `mise.toml`) supports this.
- Each surface gets its own `SelectionArea`, so Select all stays inside one item. The same separator delegate is used at the region root, so siblings outside `RichTextRenderer` (the title and body, each item in the reply preview) are separated too.
- The delegate is a `ChangeNotifier`. It is created once in the owning `State`, kept across rebuilds (a spoiler reveal must not reset the selection), and disposed in `dispose()`.
- A code block's horizontal scroller is one child selectable, so the newline goes around it, not inside it.
- Flutter's `SelectableRegion` clears the selection on an outside tap only on web (`selectable_region.dart` ~:1964, pinned 3.47.2). Mobile needs explicit handling for behaviour 8.
- Placed images, including their error fallback, go under `SelectionContainer.disabled`.
- The language label in code blocks goes inside `SelectionContainer.disabled`.

## Decisions (user, 2026-11-12)

1. **Comments are not selectable.** Long-press on a comment still collapses it. Copying a comment happens in the reply composer, which already shows it selectable.
2. **Post titles are selectable** on the detail view, in the same region as the body, so one copy can include both.
3. **No "Copy text" menu item** on feed posts or post detail. Amended 2026-11-18: comments get a **"Select text"** item in their "⋯" menu that opens a sheet with the comment's text, selectable.
4. **Display names and handles are not selectable.** The handle is already a link, and the DID has tap-to-copy.

## Out of scope

- Selection in the composer input (it already supports selection).
- Comment bodies in the thread itself (decision 1); they are selectable only in the reply composer and the "Select text" sheet.
- Changing what a tap does anywhere.

## Constraints

- Test on the physical Android phone and on an iOS simulator, plus a physical iPhone if one is available. Selection handles, the toolbar, and conflicts with scrolling and paging behave differently on real hardware.
- No new dependencies.

## Acceptance

- On each surface in "Make selectable", long-press then Copy puts the expected text on the clipboard. A widget test asserts this through the clipboard.
- A post with a title and a body containing a heading, a paragraph, a quote, a code block and a removed image copies, with Select all, to an exact literal string with one `\n` at each boundary and no "Image removed" text. A second case selects partway through two blocks and asserts the exact string. A plain-text post (no facets) copies as title, `\n`, body.
- In the reply preview, Select all on a post and on a comment chain copies the content without author names, handles or timestamps.
- Tapping outside an active region clears the selection.
- An unrevealed spoiler never appears in copied text on any surface.
- Links, mentions, spoiler reveal and image taps still work inside selectable regions, with one widget test each at the `RichTextRenderer` level.
- Long-press on a comment still collapses it.
- A comment's "Select text" menu item opens a sheet where Select all then Copy puts exactly the comment's body on the clipboard, with hidden spoilers as placeholders. The item is absent on deleted, removed and text-less comments.
- `flutter analyze` is clean and `flutter test` passes. The Android phone and iOS simulator checks have been run, including carousel swipes inside the post region.

## Implementation notes

### Chunks

- 01 Separator-aware selection region, profile bio — 9d61bd7
- 02 RichTextRenderer block separators, copy exclusions and taps — 60516e0
- 03 Post detail title and body selection — 18b1945
- 04 Community About and lightbox alt text selection — 6eb43cd
- 05 Reply preview copies content only — 1205974
- 06 Comment "Select text" menu item and sheet — 1a5f9a9
- 07 Post detail long-press claims cover banner and media padding — bd315de

### How it fits together

Interfaces, all in `lib/widgets/separated_selection_area.dart` unless noted:

- `SeparatedSelectionArea({required Widget child})`: the selectable region. Build order: TapRegion (groupId SelectableRegion, translucent, tap outside unfocuses) > Listener (pointer down unfocuses other focused areas) > hit-test exclusion > SelectionArea (owned focus node, explicit selection controls) > SelectionContainer with a `SeparatedSelectionContainerDelegate`. A tap outside clears the selection through focus loss while the app is resumed.
- `SeparatedSelectionContainerDelegate`: inserts separators between blocks when copying. `didChangeSelectables()` calls `SchedulerBinding.instance.ensureVisualUpdate()` so an area that mounts on an idle screen (tab switch, sheet open) registers its selectables; without it long-press selects nothing.
- `SeparatedSelectionContainer({required Widget child})`: a StatefulWidget whose State owns its delegate. Use it for any nested or per-block SelectionContainer. Never keep a delegate in a parent State and pass it down (null-context crash in `getTransformFrom`).
- `ContentOnlySelectionScope` (InheritedWidget, set only by ReplyScreen's preview) and `ContentOnlySelectionExclusion({required child})`: inside the scope the exclusion is `SelectionContainer.disabled` plus a no-op translucent long-press claim with `excludeFromSemantics`; outside the scope it returns the child unchanged. Applied in post_card (header, footer, banner, media, embeds, link bar), comment_card (author row, unplaced gallery, actions) and comment_thread (Read N more / Load more).
- `showCommentTextSheet(BuildContext, CommentView)` in `lib/widgets/comment_text_sheet.dart`: the comment Select text sheet. The comment ⋯ menu shows wherever a comment has text, except inside `ContentOnlySelectionScope`.

Where it is used:

- RichTextRenderer: a multi-block root Column sits in a `SeparatedSelectionContainer`; multi-block quotes get their own. The code language label and the placed-image subtree (all load and error states) are under `SelectionContainer.disabled`, and placed images carry a long-press claim. A single-block body returns early with no container, so siblings outside the renderer rely on the enclosing area's delegate for separators.
- DetailedPostView owns one `SeparatedSelectionArea` from title through body. Banner and media are under `SelectionContainer.disabled` with translucent long-press claims; author row, link bar, Bluesky card and sources sit outside the region.

Rules:

- One `SeparatedSelectionArea` per screen or surface. Don't place two areas adjacent, and don't build on the hit-test exclusion logic (see open items).
- Nested containers are element-owned: use `SeparatedSelectionContainer`, not a shared delegate.
- A scrollable inside a selection area sits inside the `SeparatedSelectionArea` (area > SingleChildScrollView > Text), never around it, or handles leak outside the clip and drag does not auto-scroll.
- Any non-text widget inside an area needs a long-press claim: `GestureDetector(behavior: HitTestBehavior.translucent, onLongPress: () {}, excludeFromSemantics: true, child: ...)`. Without it long-press selects the nearest word. `deferToChild` leaves gaps (padding, Spacer) that fall through; omitting `excludeFromSemantics` adds a longPress semantics action and merges labels.
- `SelectionContainer.disabled` children register no selectable; that is Flutter's own behaviour.

Test conventions:

- Use `TargetPlatformVariant.only`, not `debugDefaultTargetPlatformOverride` in setUp/tearDown.
- Set `AppLifecycleState.resumed` and pump an extra frame after mounting.
- Every MaterialApp needs `theme: AppTheme.dark` (guarded by `test/theme/no_bare_material_app_test.dart`).
- The test toolbar can overlap neighbours at 400x900; pick target words that stay clear of it.
- Semantics lookups under a selection area target the RichText descendant, not the Text (a MouseRegion sits above it).
- A hidden handle is unlinked (`CompositedTransformFollower` `link.leader == null`), not faded.
- Escape does not close the comment MenuAnchor in widget tests; tap the trigger again.

### Open items

- Deferred from chunk 01 review: when two `SeparatedSelectionArea`s are adjacent, the handle-target hit-test exclusion applies even when no handles are shown, and its geometry can go stale if the selected text moves. No screen places two areas adjacent today.
- Deferred suggestion: on long About, bio or post bodies, dragging a handle to the screen edge does not auto-scroll the page (the area sits under the page scroll view).
- Decided 2026-11-19: the comment Select text sheet keeps images placed inside the comment's text (better UI); only gallery images are left out. Behaviour 10 updated.
- Decision taken in the loop: Select text is not offered inside the reply preview (already selectable). The ⋯ menu now appears on text comments where it was hidden before (for example signed out, profile comment lists).
- Maestro `h2_rich_text_linkbars` fails on main too: the app labels links "dawn.com", the flow expects "[dawn.com]".
- `docs/QA_LOOP.md` says QA account mari has no bio; it has an imported one.
- Device checks not yet done: profile bio Maestro flow (draft only); post-detail scroll and pull-to-refresh by hand on a long post; lightbox swipe with the alt panel open; reply-to-comment preview copy by hand; iOS simulator for all surfaces.

### Maestro

- New flow: `.maestro/c9_comment_select_text.yaml`.
