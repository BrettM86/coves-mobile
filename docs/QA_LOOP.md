# Coves Mobile — QA Verification Loop

Reference spec for the recurring emulator-based QA loop. Each iteration of the
loop picks the next section below (round-robin), spawns a QA subagent that
exercises it end-to-end on the Android emulator against the **local** backend,
fixes any bugs found, and commits the fixes.

## Ground rules (every iteration)

- **One QA agent drives the emulator at a time.** Never run two
  emulator-driving agents in parallel; read-only code-audit agents may run
  alongside.
- **Local backend only.** `flutter run --flavor dev` alone still talks to
  PRODUCTION — always pass `--dart-define=ENVIRONMENT=local`.
- **Test account**: handle `mari.local.coves.dev`, password `password`.
- **Verify before fixing**: reproduce the bug on the emulator, fix it, then
  re-run the same steps to confirm the fix.
- **Quality gates before any commit**: `flutter analyze` clean, and
  `flutter test <related dirs>` passing.
- **Commit style** (matches history — conventional commits, scoped):
  `fix(comments): handle absent author on deleted comments`. One logical fix
  per commit. Another agent may be committing too — `git pull --rebase` before
  pushing/committing, and only ever commit files you changed.
- **Log every run**: append a row to `docs/QA_LOOP_LOG.md`
  (`| date | section | result | bugs found | commits |`). Create the file with
  that header if missing.

## Environment playbook

### 1. Backend stack (usually already up)
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/xrpc/_health  # expect 200
# If down:
cd /Users/bretton/Code/coves && make dev-up
```

### 2. Emulator
```bash
adb devices   # if empty:
~/Library/Android/sdk/emulator/emulator -avd Medium_Phone_API_36.1 -no-snapshot-save &
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'
# Port-reverse the local stack (required every boot):
for p in 3001 3002 8080 8081; do adb reverse tcp:$p tcp:$p; done
```

### 3. Run the app
```bash
cd /Users/bretton/Code/coves-mobile
flutter run --flavor dev --dart-define=ENVIRONMENT=local
# (run in background; hot reload with `r` is unavailable non-interactively —
#  rebuild or use `flutter run --machine` if needed)
```

### 4. Driving the UI — Maestro first, adb as fallback

**Primary: Maestro** (installed via Homebrew; needs Android Studio's JDK):
```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
maestro test .maestro/<flow>.yaml            # run a flow
maestro hierarchy                            # inspect the semantics tree (find selectors)
```
Flows live in `.maestro/` at the repo root, named `<section-letter>_<flow>.yaml`
(e.g. `a_login.yaml`). **Write each check as a flow and COMMIT passing flows** —
they accumulate into a regression suite that later iterations re-run first.
Example:
```yaml
appId: social.coves.dev
---
- launchApp
- tapOn: "Sign in"                 # matches semantics label / visible text
- tapOn: "Handle"
- inputText: "mari.local.coves.dev"
- tapOn: "Continue"
- assertVisible: "Home"            # auto-waits; fails with a screenshot
- takeScreenshot: scratch/a2_logged_in
```
Maestro reads Flutter's accessibility tree and can also drive native UI
(OAuth browser tab, permission dialogs). If a widget isn't findable, add a
`Semantics` label/tooltip to it in the app — that's a legitimate a11y fix,
commit it as one.

**Fallback: raw adb** (coordinate-based — only when Maestro can't do it):
```bash
adb exec-out screencap -p > shot.png        # then Read the image to inspect
adb shell input tap <x> <y>
adb shell input text 'hello%sworld'          # %s = space
adb shell input keyevent 66                  # enter
adb shell uiautomator dump && adb pull /sdcard/window_dump.xml  # widget tree
```

**Durable in-app tests**: for pure in-app flows (no OAuth tab, no native
dialogs), also consider seeding `integration_test/` cases — they're the best
long-term regression artifact. Don't block a section run on this.

### 5. Legal-gate bypass (fresh installs, debug builds)
The EULA checkbox requires scrolling the entire agreement — bypass instead:
```bash
adb shell am force-stop social.coves.dev
# via run-as social.coves.dev, add to shared_prefs/FlutterSharedPreferences.xml:
#   <long name="flutter.eula_accepted_version" value="1"/>
#   <long name="flutter.community_guidelines_accepted_version" value="1"/>
```
(Do NOT bypass when testing Section G — the gates ARE the test there.)

### 6. Cold-load deep link (no http intent filters exist; use explicit component)
```bash
adb shell am start -n social.coves.dev/social.coves.MainActivity \
  -a android.intent.action.VIEW \
  -d 'social.coves:///post/<percent-encoded at:// URI>'   # note THREE slashes
```

---

## Section A — Auth & Session

**Code**: `lib/screens/auth/`, `lib/screens/landing_screen.dart`,
`lib/services/coves_auth_service.dart`, `lib/services/auth_interceptor.dart`,
`lib/services/pds_discovery_service.dart`, `lib/providers/auth_provider.dart`,
`lib/widgets/sign_in_dialog.dart`, `lib/widgets/bluesky_sign_in_button.dart`

**Emulator checks**
1. Fresh install → landing screen renders, no overflow/blank states.
2. Sign in with `mari.local.coves.dev` / `password` → OAuth completes, lands
   on home feed.
3. Kill the app (`adb shell am force-stop social.coves.dev`), relaunch →
   session persisted, no re-login.
4. Wrong password → graceful error, no crash, can retry.
5. Sign out → returns to landing, tokens cleared (no authed calls succeed).
6. Airplane-mode login attempt (`adb shell cmd connectivity airplane-mode enable`)
   → friendly error, restore afterwards.

**Static checks**: tokens only in flutter_secure_storage; no tokens in logs;
`flutter test test/services test/providers`.

## Section B — Home Feed

**Code**: `lib/screens/home/feed_screen.dart`, `lib/screens/home/main_shell_screen.dart`,
`lib/providers/multi_feed_provider.dart`, `lib/providers/vote_provider.dart`,
`lib/widgets/feed_page.dart`, `lib/widgets/post_card.dart`,
`lib/widgets/post_card_actions.dart`, `lib/widgets/post_action_bar.dart`

**Emulator checks**
1. Feed loads with visible loading state (no blank flash), posts render.
2. Scroll 30+ posts: no jank, no overflow boxes, images load, list recycles.
3. Pull-to-refresh works; pagination fetches next page at bottom.
4. Upvote/downvote a post → optimistic update, survives refresh; un-vote works.
5. Switch feed tabs (if present) → each retains scroll position/state.
6. Airplane mode + refresh → error state with retry, not a crash.

**Static checks**: `flutter test test/widgets test/providers`.

## Section C — Post Detail & Comments

**Code**: `lib/screens/home/post_detail_screen.dart`, `post_detail_loader.dart`,
`focused_thread_screen.dart`, `lib/providers/comments_provider.dart`,
`lib/services/comment_service.dart`, `lib/services/comments_provider_cache.dart`,
`lib/widgets/comment_thread.dart`, `comment_card.dart`, `comment_composer.dart`,
`comments_header.dart`, `detailed_post_view.dart`

**Emulator checks**
1. Tap a feed post → detail renders full content + comments.
2. Cold-load: deep link straight to a post (playbook §6) with app killed →
   loads via `social.coves.community.post.get`, no crash.
3. Comment thread: nesting renders, collapse/expand, load-more replies.
4. Post a comment → appears in thread; reply to a comment → correct nesting.
5. Deleted comment with absent author renders placeholder (regression:
   652f075), no crash.
6. Vote on comments; comment sort (if present); keyboard doesn't cover the
   composer (`resizeToAvoidBottomInset`).
7. **Deep chains** (seed via API if needed — reply chain of 15–20 nested
   comments, alternating authors mari/test-aggregator): full chain renders in
   correct nesting order with no overflow/clipped indent rails at max depth;
   "load more replies" appears past the fetch depth/limit and each load
   continues the chain correctly; collapse/expand works at deep levels;
   scroll performance stays smooth through the chain.
8. **Focused thread screen** (`focused_thread_screen.dart` — the
   "continue thread" view): entering it from a deep comment shows the right
   subtree rooted at that comment; replying from inside it lands the reply at
   the correct depth and it appears in both the focused view and the full
   thread; back returns to the parent thread at the right position; deep-link
   cold-load into a focused thread doesn't crash.

**Static checks**: `flutter test test/widgets test/services`.

## Section D — Communities

**Code**: `lib/screens/home/communities_screen.dart`,
`communities_discovery_screen.dart`, `communities_see_all_screen.dart`,
`communities_admin_panel.dart`, `lib/screens/community/community_feed_screen.dart`,
`lib/providers/community_subscription_provider.dart`,
`lib/widgets/community_*.dart`, `tappable_community.dart`

**Emulator checks**
1. Communities tab → discovery screen renders (browse + search + widgets —
   regression: 55f15fb).
2. Search communities: results update, empty-query and no-results states.
3. Open a community → feed loads, header/avatar/hero card render.
4. Join → button state flips, feed reflects membership; leave → reverts.
5. See-all screen paginates; admin panel opens without crash (if accessible).
6. Community chips/tappable-community navigate correctly from feed posts.

**Static checks**: `flutter test test/screens test/widgets`.

## Section E — Compose & Posting

**Code**: `lib/screens/home/create_post_screen.dart`,
`lib/screens/compose/community_picker_screen.dart`, `reply_screen.dart`,
`lib/widgets/image_source_picker.dart`, `lib/services/streamable_service.dart`

**Emulator checks**
1. Create post: pick community, title + body, submit → appears in community
   feed and cold-loads by deep link.
2. Validation: empty title/body blocked with clear message; over-length input
   handled.
3. Community picker: search, select, cancel — state consistent after each.
4. Reply screen: open from comment, submit, cancel-with-draft behavior.
5. Keyboard behavior: no overflow, fields visible while typing.
6. Kill app mid-compose → no crash on relaunch (draft loss acceptable, crash
   is not).

**Static checks**: controllers disposed (grep `TextEditingController` for
matching `dispose()`); `flutter test test/screens`.

## Section F — Profile

**Code**: `lib/screens/home/profile_screen.dart`, `edit_profile_screen.dart`,
`lib/providers/user_profile_provider.dart`, `lib/widgets/profile_header.dart`,
`tappable_author.dart`

**Emulator checks**
1. Own profile tab renders: avatar, handle, stats, posts list.
2. Tap an author in the feed → their profile opens.
3. Edit profile: change display name/bio → persists after app restart.
4. Avatar change flow opens image picker without crash (emulator has no
   camera — gallery path only).
5. Profile of user with no posts → sane empty state.

**Static checks**: `flutter test test/providers test/screens`.

## Section G — Moderation, Safety & Legal Gates

**Code**: `lib/providers/block_provider.dart`, `eula_provider.dart`,
`community_guidelines_provider.dart`, `lib/widgets/block_action_helpers.dart`,
`report_dialog.dart`, `lib/screens/eula_screen.dart`,
`community_guidelines_screen.dart`

**Emulator checks** (use a FRESH install; do NOT bypass gates here)
1. EULA gate: shown on first launch, accept requires full scroll, acceptance
   persists across restart.
2. Community guidelines gate (regression: 1481ef9): same lifecycle.
3. Report a post → dialog opens, reasons selectable, submit + cancel work.
4. Block a user → their content disappears from feed; unblock restores.
5. Blocked-state edge cases: viewing a blocked user's profile, their comments
   in threads.

**Static checks**: `flutter test test/providers`.

## Section H — Media & Rich Content

**Code**: `lib/widgets/fullscreen_video_player.dart`,
`minimal_video_controls.dart`, `rich_text_renderer.dart`,
`external_link_bar.dart`, `source_link_bar.dart`, `bluesky_post_card.dart`,
`share_button.dart`, `lib/utils/`

**Emulator checks**
1. Post with video: inline plays, fullscreen toggle, controls
   show/hide, back gesture exits cleanly (player disposed — no audio after
   exit).
2. Rich text: links, mentions, formatting render; tapping a link opens
   browser/in-app correctly.
3. External/source link bars show domain and open target.
4. Bluesky-sourced post card renders distinctly and doesn't crash on missing
   fields.
5. Share button produces a share sheet with a sensible URL.
6. Rotate device during video playback → no crash, state preserved.

---

## Iteration protocol (what the loop does each wake)

1. Read `docs/QA_LOOP_LOG.md`; pick the next section round-robin (A→H, wrap).
2. Verify env: backend health, emulator booted, `adb reverse` applied.
3. Spawn ONE QA subagent with: this file's ground rules + playbook + the
   section's checklist. It tests on the emulator, screenshots as evidence,
   fixes bugs it can verify, runs analyze/tests, commits per the style above.
4. If the subagent reports bugs it could not fix, record them in the log row
   as `OPEN: <desc>` so a later iteration (or the user) picks them up.
5. Append the log row, then schedule the next wake.
