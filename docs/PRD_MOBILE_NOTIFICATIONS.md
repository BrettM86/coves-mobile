# Mobile in-app notifications PRD

Status: approved for build 2026-10-08. Repo: `coves-mobile`.
Backend: done and pushed (coves `654377d`). The wire contract, server rules and product decisions are in `~/Code/coves/docs/PRD_NOTIFICATIONS.md` (decisions 1–9, "Unread and seen", "Pagination", "Lexicons", "Mobile") and `~/Code/coves/docs/NOTIFICATIONS_IMPLEMENTATION.md` (section 2 Q-decisions, "Read path", section 4 "Clients"). The lexicons are in `~/Code/coves/internal/atproto/lexicon/social/coves/notification/`. This document records only the mobile decisions. Where it is silent, the backend PRD's "Mobile (`coves-mobile`)" section applies.

## Base

- Built on `prd/prd_mobile_moderation_admin` (tip `e27bd75`), which is treated as final. It provides `RemovalCopy` (`lib/utils/removal_copy.dart`), the moderation-aware `PostDetailScreen`/`PostDetailLoader`, and the `CursorPaginationController` changes. Upstream moderation changes are rebased in later.
- The bell tab already exists as tab 3 in `lib/screens/home/main_shell_screen.dart` (phone bottom bar `_buildNavItem(3, 'bell', …)` and tablet `NavigationRail`). It is lazily built and then kept alive offstage in an `IndexedStack`.

## Decisions (user, 2026-10-08)

1. **API on the shared `CovesApiService`.** The five `social.coves.notification.*` calls are methods on the app's one `CovesApiService` (injected, never disposed), not a separate service with its own Dio.
2. **Signed out:** the Notifications tab shows a sign-in prompt using the existing sign-in gate (returns to origin). No badge, no polling, no requests while signed out.
3. **No Mentions tab in v1.** One list. (The backend has no reason filter.)
4. **Settings:** a new Settings screen, reached from Profile → top-right hamburger sheet → "Settings". It has a Notifications section with four switches backed by `getPreferences`/`putPreferences`. A gear icon in the Notifications app bar opens the same screen. The gear is hidden when signed out.
5. **Placeholder text** reuses `RemovalCopy`: `deleted` → `RemovalCopy.deletedByUser`, `removedByModerator` (community scope) → `RemovalCopy.removedByCommunityModerator`, `removedByServerAdmin` → `RemovalCopy.removedByServerAdmin`. Placeholder text replaces only the reference that carries the status (title, preview or excerpt); the row still renders and still navigates.
6. **No action row** on any notification. Tapping a row opens the thread.
7. **Sign-in return-to-origin** (main `a5c9c65`) is cherry-picked onto the integration branch at creation, so the tab's sign-in prompt returns to the Notifications tab.
8. **Removed or deleted root post:** the server omits `rootPost.community`, so the reply/mention card hides its header row entirely and starts with the `RemovalCopy` text in the title position.
9. **DID-only actors** (no handle, no display name) show the default avatar and "Unknown user", with no handle line, in both card authors and upvoter names.
10. **NSFW accessibility:** a concealed row is two semantics nodes. The row button's label leaves out the concealed text and the thumbnail alt. The `SensitiveContentBanner` "Show" button sits inside it as a separate node.
12. **"Displayed" means visible.** Marking seen and the page-one reloads run only while the Notifications tab is selected and the shell route is on top. While a thread or Settings route covers the shell, they wait until that route is popped.
11. **Design** merges two references (Bluesky's notification list and Voyager's comment-reply cards), in Coves' own theme (`AppColors`, `AppTypography`, Lucide icons via `AppIcon`). Final spacing and sizing are adjusted by the user on a device after the build.

## Behaviour

### Unread badge
- Shown on the bell in both the phone bottom bar and the tablet `NavigationRail` when signed in and the count is above 0. Count 1–99 shows the number. Above 99 (the API caps at 101) it shows "99+".
- `getUnreadCount` is fetched on sign-in or app start with a restored session, every 30 seconds while the app is foregrounded, on `AppLifecycleState.resumed`, and on every tab switch. Polling stops when the app is backgrounded and when signed out.
- Signing out or switching accounts clears the count at once. A response that belongs to a previous session is discarded (session-generation guard, as other providers do).
- A failed count fetch keeps the last known count and does not show an error.

### List
- Paginated with `CursorPaginationController`, using the server default page size (50).
- Paging continues while `cursor` is present, even when a page comes back short or empty.
- Pull-to-refresh replaces page one.
- `InvalidCursor` (HTTP 400) on a later page uses the Discover recovery: replace page one once, then show a manual retry footer.
- Empty state ("No notifications yet"), full-screen retryable error for page one, a retry footer for later pages, and 401 through the existing session-expiration flow.
- Rows with an unknown `reason` are skipped. A reference with an unknown `status` value renders `RemovalCopy.removedByModerator`.

### Seen state (backend PRD "Unread and seen")
- After page one has been displayed **while the Notifications tab is the selected tab**, call `updateSeen` with the largest `sortAt` among page one's rows, echoed as the exact string the server sent (never re-serialized through `DateTime`). Skip it when page one is empty. Never send the device clock.
- After `updateSeen` succeeds, refetch `getUnreadCount` to set the badge. The badge is not optimistically zeroed.
- Rows on page one use the server's `isRead`. Rows on page two and later have `isRead` computed against page one's `seenAt`: read when `sortAt <= seenAt`, and all read when page one's `seenAt` was null.
- Page one is reloaded, then marked seen again, when the tab is selected and the unread count is above 0, and when the count rises while the tab is selected.
- `updateSeen` failures are silent apart from crash reporting. `AccountNotIndexed` is silent.

### Navigation
Every row opens `/post/<rootPost.uri>`, with `?comment=` set as follows:

| Reason | Focused comment |
|---|---|
| `postReply`, `commentReply` | `record.uri` |
| `mention` whose `record` is a comment | `record.uri` |
| `mention` whose `record` is a post | none (open `record.uri` as the post) |
| `upvote` whose `subject` is a comment | `subject.uri` |
| `upvote` whose `subject` is a post | none |

Placeholder rows navigate the same way, and the thread shows its own deleted or removed state.

### Row design

**Upvote groups**, a compact row in the style of Bluesky's "liked your post":
- Leading heart icon, filled in the upvote colour. Coves upvotes are hearts.
- An avatar stack of `recentUpvoters` (up to 3).
- Text: "**alice** and **12 others** liked your post", or "your comment". Others = `upvoteCount − 1` when there are upvoters. When there are 2 or 3 upvoters and no others: "**alice** and **bob** liked…" / "**alice**, **bob** and **carol** liked…". With no upvoters (bridged only): "**5 people** liked your post", or "**1 person**".
- Below the text: `subject.preview` (post title, body excerpt, or comment excerpt), 2–3 lines, muted.
- A small square `subject.thumbnail` (52px) beside the preview, on its trailing side, when present, with `thumbnailAlt` as its semantics label. With no preview the thumbnail still sits below the text, right-aligned.
- Time is `sortAt`, relative ("6d"), in its own muted text at the top right: at the end of the avatar row, or at the end of the text's first line when there are no avatars. An unparsable `sortAt` shows no time.

**Replies and mentions**, a roomier card in the style of Voyager's "Comment reply":
- Header row: community avatar (`rootPost.community.avatar`), then two lines. The first is the reason ("Reply to your post", "Reply to your comment", "Mentioned you"). The second is the community as `!name@origin` in the existing community-name format. Relative time from `record.createdAt` on the right.
- The post title (`rootPost.title`) in a larger style, with `rootPost.thumbnail` on the trailing side when present. Both are omitted when absent.
- A quoted bubble, indented, holding:
  - the author's avatar beside it;
  - the author's display name (or handle) and `@handle`, from `author`;
  - `record.excerpt`.
- For a `mention` whose `record` is a post, the bubble shows the author line and `record.excerpt` only when it differs from `rootPost.title`.
- When the record's placeholder repeats the root's for the same cause, the placeholder shows once, in the title position, and the bubble shows only the author line. The same cause is the same post (a `mention` whose post is deleted or removed) or a root removed by a moderator or server admin, whose removal the server folds into the comment. Independent author deletions of the root and the record, and different placeholder copies, keep both.
- Rows are full width with no gap between them, each divided from the next by a 0.5px `AppColors.borderWarm` bottom hairline, as feed posts are.

**Both kinds:**
- Unread rows show an 8px coral dot before the timestamp. Read and unread rows share the background. The row label starts with "Unread" on an unread row.
- A reference whose `labels` contain an active `nsfw` value is concealed. The concealed parts are its text (title, preview or excerpt) and the thumbnail of any reference in the row; they are replaced by the existing `SensitiveContentBanner`, which reveals that row only. Reveal state is keyed by the row and resets on reuse. The row header (who, what, when) stays visible.
- Each row is one semantics node with a label that reads like the visible sentence, and it is a button that navigates. The label uses the actor's name (display name, else handle, else "Unknown user") without the `@handle`.

### Settings screen
- New route (for example `/settings`), opened from a new "Settings" entry in the Profile hamburger sheet and from the Notifications app bar gear.
- The Notifications section has four switches, labelled "Replies to your posts", "Replies to your comments", "Mentions" and "Likes", loaded from `getPreferences`. A loading state and a retryable load error are shown.
- Toggling sends `putPreferences` with only that key and applies the full object it returns. The switch moves optimistically; on failure it reverts and a snackbar explains. `AccountNotIndexed` shows "Your account is still being set up. Try again in a minute."
- Turning a reason off or on refetches the unread count. The list reloads page one the next time it is shown.

## Testing
- Host tier only for the `/tdd` contract (unit and widget tests in `test/`, mocked `CovesApiService`), per the repo profile.
- Device verification:
  - A Maestro flow per visible surface: badge, list, row kinds, navigation, settings.
  - The backend PRD's local-stack integration: two real local accounts on the local PLC/PDS. Account A replies to, mentions and upvotes B's content; B sees the badge, opens the list, rows navigate correctly, and the badge clears.
  - The local stack runs without the image proxy, so thumbnails are not visible locally. Device checks cover their absence; production shows them.
- After the build, the user reviews the design on a physical device and adjusts it.

## Out of scope
Push notifications, a Mentions tab or reason filter, per-row mark-read, row actions (reply, report), expanding an upvote group to all voters, video thumbnails, community content warnings.

## Implementation notes

Built by /prd-loop on `prd/prd_mobile_notifications`, 2026-10-08 to 2026-10-12. Not merged to main.

### Chunks

Base: `dcf7b0d` cherry-picks main `a5c9c65` (sign-in prompt returns to origin, decision 7) onto the moderation tip `e27bd75`; `e59d1e8` adds this PRD.

- 01 Unread badge — `a4ba2be`
- 02 Notification wire layer — `dbebcf4`
- 03 Reply and mention card — `39887f9`
- 04 Upvote group row — `1e78547`
- 05 Settings screen — `6709ee0`
- 06 List first page — `c010d8f`
- 07 List paging and recovery — `cd919ae`
- 08 Mark seen — `7d8c335`
- 09 Reloads and Settings gear — `e13e1e3`
- 10 Read state and unread tint — `2709d6f` (the tint was later replaced by an unread dot)
- 11 Sensitive content — `55a0e35`
- 12 Settings session ownership — `2e119b0`
- 13 Row design adjustments — `0cfc70d`

### Interfaces and contracts

**Providers and session keys**
- Session-scoped state is keyed by `ViewerAuthorityProvider.sessionKey`, a record `({did, generation})`. `main.dart` passes `sessionKeyOf: () => viewerAuthorityProvider.sessionKey` to `NotificationsListProvider` and `NotificationPreferencesProvider`. Never compare a session stamp with a DID string. Test harnesses wire it the same way.
- `UnreadNotificationCountProvider` (`lib/providers/unread_notification_count_provider.dart`) is registered in `main.dart`. Call `refresh()` to refetch; each call starts a new generation and the latest wins. Any lifecycle state other than `resumed` (including `inactive`) stops the 30 s poll. `MainShellScreen._selectTab` refreshes on every tab change. Tests register it with `unreadNotificationCountRegistration` in `test/test_helpers/fake_providers.dart`; new shell harnesses need it.
- `NotificationsListProvider` (`lib/providers/notifications_list_provider.dart`): the screen's only request paths are the guarded `requestFirstPage()`, `loadMore()`, `retryLoadMore()`, `refresh()` (returns bool) and `markPageOneSeen()`. `controller` is public but read-only by convention. The screen calls `requestFirstPage()` post-frame on every signed-in build, and that is the only trigger that loads after sign-in. Page one is a nullable record `({rows, sessionStamp, marked})`. After a failed page-one refresh the old rows stay on screen but cannot be marked seen until a reload succeeds.
- `markPageOneSeen()` sends `updateNotificationsSeen` with page one's largest raw `sortAt`, then refreshes the unread count, with session-generation guards. A row whose `sortAt` cannot be parsed is skipped.
- InvalidCursor recovery replaces page one once. Only `refresh`, `retryLoadMore` or an account change re-arms it.
- `NotificationPreferencesProvider` (`lib/providers/notification_preferences_provider.dart`) is app-level and owns the loaded values, the pending-toggle overlay, the serial update queue and the load error. A session-key change drops all of it, and responses for an older session are ignored. `SettingsScreen` (`lib/screens/settings/settings_screen.dart`, route `/settings`, reached from the Profile menu "Settings" tile and the Notifications gear) is a view over it. It calls `reloadOnOpen` from `initState` and `loadIfNeeded` in `didChangeDependencies`. Signed out, it shows a `PrimaryButton('Sign in')` that pushes `/login`. A successful update bumps `NotificationPreferencesChangeSignal` and refreshes the unread count.
- `NotificationsScreen` (`lib/screens/home/notifications_screen.dart`) tracks the last signal version it consumed. On a session-key change it consumes the pending bump and clears `_revealedIdentities`. Reloads are `_reloadPending` plus the version check, coalesced through a post-frame `_scheduleReload`.

**Visibility.** "Visible" (decision 12) means the Notifications tab is selected and the shell route is on top. `appRouteObserver` (`lib/utils/app_route_observer.dart`) is registered in `createRouter`. `NotificationsScreen` is `RouteAware`, and `_isVisible` and `didPopNext` drive marking seen and reloads.

**Models, routes and timestamps**
- The models are in `lib/models/notification.dart`. `NotificationView.tryFromJson` skips rows it cannot parse. Labels that fail to parse become null, and a non-string `status` becomes null (fail open). `NotificationReference.placeholderCopy` maps status to `RemovalCopy`. `NotificationReference.isSensitive` uses the public `parseSelfLabels` from `lib/models/post.dart`, so malformed labels read as not sensitive.
- Row identity is `NotificationView.identity`: `<reason>|<record.uri>`, or `upvote|<subject.uri>`. Paging dedup and reveal state both use it.
- `NotificationView.withReadState({required bool isRead})` copies every other field. Any new `NotificationView` field must be added to it, or later-page rows lose that field.
- Routes come from `notificationRoute` in `lib/utils/notification_navigation.dart`.
- `compareNotificationTimestamps(a, b)` in `lib/utils/notification_timestamp.dart` compares at nanosecond precision. It throws `FormatException` (without the input value) on unparseable input, so callers catch it per row. The original strings are always what is sent.
- Page one's `seenAt` is carried on a private `_PageOne`. `_laterPageBoundary` is set only from the `onFirstPageAccepted` hook and cleared on account change or controller reset. Later-page rows get a computed `isRead`, and a row that cannot be compared keeps the server value.

**CursorPaginationController** (`lib/utils/cursor_pagination_controller.dart`). The additions are all opt-in and default to the old behaviour:
- `followCursorPastEmptyPages`: stops when the cursor repeats.
- `loadMoreErrorCause`.
- `replaceFirstPageForLoadMore()`.
- `onFirstPageAccepted(CursorPage<T>)`: fires only on the accepted path, before listeners; a superseded first page never reaches it.

The notifications viewport-fill check calls `isNearScrollEnd` and `provider.loadMore()` directly in a post-frame callback, not `PaginationScrollListener.checkNow()`, whose throttle drops calls.

**Log redaction**
- `isPrivateNotificationPath` (`lib/services/log_redaction.dart`) matches `startsWith('/xrpc/social.coves.notification.')`, so pass relative paths. Notification routes log only method, path and status. This covers `mapDioException`, the auth interceptor's error lines and `_request`'s parse-failure line.
- `_request`'s `redactParseErrorDetail` is opt-in per caller; all five notification calls pass it.
- `ApiException.message` for an `HttpException` embeds the full URL including `?cursor=`. Never log `$e` for notification errors.

**Row widgets**
- `NotificationReplyCard` and `NotificationUpvoteRow` are in `lib/widgets/notifications/`. They take `notification`, `onTap`, `currentTime`, `sensitiveContentRevealed` and a required `onSensitiveContentToggle`. Sizes are private consts at the top of each file. `upvoteNotificationSentence` in `lib/utils/upvote_notification_copy.dart` returns `(text, bold)` parts.
- Semantics: a row without a sensitive banner is one `Semantics(button, label, onTap, excludeSemantics: true)` node. A row with a banner is `Semantics(container: true, button: true)`, with `ExcludeSemantics` around every part except the banner and `InkWell(excludeFromSemantics: true)`. Labels use the actor's name only, never the `@handle`.
- Unread rows put `NotificationUnreadDot` (8px, `AppColors.primary`) before the timestamp, through `NotificationTimeLabel` in `lib/widgets/notifications/notification_post_card.dart`. Read and unread rows share the background. Unread row semantics labels start with "Unread".
- User decisions of 2026-10-12: the upvote heart is filled in `AppColors.voteLiked`. A repeated `RemovalCopy` placeholder shows once, in the title position, for a post mention whose record is the root, or for a root removed by a moderator or server admin. Independent author deletions and differing copies keep both.

**Other**
- Sentry reporting is out of scope for this feature.
- Since the `a5c9c65` cherry-pick, an account change in `FocusedThreadScreen` cancels in-flight ancestor refreshes and resets removal sequence numbers.
- On this branch, `auth_interceptor.dart` reports a failed post-refresh retry (500, timeout, connection error) as the original 401. Main `cf67a46` fixes this. Until the branch picks it up, widget tests mock at the `CovesApiService` boundary.
- Test harness facts:
  - Tests using `ensureSemantics` call `semantics.dispose()` at the end of the body, not in `addTearDown`.
  - With go_router 18, read `router.state.uri` after `push`.
  - http_mock_adapter 0.6.1 keeps the map given at registration, so use `replyCallback` for bodies that change mid-test.
  - Pull-to-refresh needs a fling of at least 25% of the viewport.
  - The shared harnesses are `test/test_helpers/notifications_screen_harness.dart` and `notifications_list_provider_harness.dart`.

### Deferred findings still open

**Unread badge**
- Any non-resumed lifecycle state, including `inactive` (system dialogs, the notification shade), stops polling.
- Overlapping `refresh()` calls are not coalesced.
- `refresh()` does not wait out `AuthProvider.isLoading`.
- No test covers listener notification on an account switch or a lower bound on the 30 s period.

**Wire layer**
- `isPrivateNotificationPath` uses `startsWith` on the relative path, while the moderation check uses `contains`; an absolute URL is not recognised.
- `redactParseErrorDetail` is opt-in, so a new notification call that omits it logs raw parse errors. No test pins the flag on the preference calls.
- `tryFromJson` drops unparseable rows without a trace.
- A non-string `status` renders the reference as live.
- `identity` relies on `record!`/`subject!` with no assert, and `recentUpvoters` is a mutable list.

**Row widgets**
- `NotificationReplyCard._isPostUri` duplicates `moderationSubjectUriKind`.
- Thumbnail placeholder and error widgets are blank boxes in both rows, not the `MediaFill` placeholder.
- `showsHeader` controls both the header row and the time.
- The comment above `repeatsRootPlaceholder` reads inverted.
- No test covers placeholder-once for a mention of a comment under a removed root, or for an unknown root status.
- Decision 5 above still says the placeholder replaces only the reference that carries the status, which predates the placeholder-once rule.
- An upvote row with no upvoters and a missing or zero `upvoteCount` renders "0 people". The parser could drop these rows; the backend never sends them.
- The upvote row does not assert its reason, and its `take(3)` avatar cap is unpinned.

**List**
- `controller` is public, so a caller can bypass the provider's signed-out guards.
- Every page-one failure shares one error message.
- No progress indicator shows while InvalidCursor recovery replaces page one.
- The viewport-fill check ignores `controller.error`.

**Seen state and reloads**
- `appRouteObserver` is a global.
- `_scheduleReload` does not call `ensureVisualUpdate`.
- A failed reload consumes its trigger.
- A screen recreated after a preference bump adopts the current version and skips that reload.
- Sign-in can load page one twice.
- A preference bump and a count rise in different frames reload twice.
- `_reloadPending` is not reset on a session change.
- `NotificationPreferencesChangeSignal` has no doc comment.

**Read state**
- A malformed non-null `seenAt` falls back per row, not once per page.
- The no-boundary fallback in `_withEffectiveReadState` is unreachable and unasserted.
- The hydration-hook failure `debugPrint` prints `$error`, and no test covers a throwing hook.
- `isRead` has no doc saying it is the server value on page one and computed on later pages.

**Sensitive content**
- `onSensitiveContentToggle` is optional, with a `() {}` fallback.
- Banner ripple behaviour is unchecked on a device.
- Reveal state survives pull-to-refresh and is never pruned; only a session change clears it.
- Labels are re-parsed on every `isSensitive` read.
- Reveal is keyed by URI, not CID, so an edited record stays revealed.

**Settings**
- No `hideCurrentSnackBar` before a new failure snackbar.
- `_sendPending` has no try/finally around `onFailure` and the signal bump; a throw leaves `_isSending` true.
- The session-mismatch `break` in `_sendPending` leaves the queue in place (latent; `_onAuthChanged` clears it).
- A toggle during the sign-out `isLoading` window can still send.
- The `_onAuthChanged` reset list must be kept in sync with new fields by hand.
- Retry ordering against queued toggles is untested.

**Docs**
- The repo `CLAUDE.md` says models use `freezed`; the notification models are hand-written.

### Device verification

These ran on the Android emulator against the home-pc local stack.
- Passed:
  - a1 and i5 (Settings via the gear, toggle, back, reload), clearing 05 and 09;
  - i2;
  - an ad-hoc two-account integration (`notifier.local.coves.dev` acting on `mari.local.coves.dev`): the badge appears and clears, mention rows and concealed NSFW mention rows navigate, Show reveals one row, and the unread tint (since replaced by the unread dot) is visible. This clears 01, 06, 07, 08, 10 and 11;
  - a1, i5 and i2 again after 12;
  - a1 and i2 after 13, with the filled heart seen.
- The flows i1–i5, the seed subflow and `docs/QA_LOOP.md` Section I are in the repo.
- Blocked: i1, i3 and i4. On home-pc, posts by human accounts stay `pending` community admission, and `listNotifications` drops reply and upvote rows whose root is not admitted, so only mention rows reach the app. The placeholder-once card could not be reached for the same reason.

Still owed on a physical device:
- Chunk 01 OAuth return-to-origin: sign out, open Notifications, Sign in, complete OAuth, land back on the tab with the badge; then kill and relaunch, and the session and badge are restored. This also covers the `a5c9c65` cherry-pick.
- Chunk 12: with Settings open, sign out and switch accounts. Settings shows the Sign in prompt, then the new account's values, and no old toggle is sent.
- TalkBack on the NSFW banner. The emulator hierarchy shows "NSFW Content" and "Show" as child nodes inside the "Show sensitive content" banner node.
- The placeholder-once card.
- The user's design review of the badge, list, both row kinds and Settings (decision 11).

### Related backlog issues

- `~/Code/claude-skills/issues/2026-09-28-mobile-auth-network-lows.md` is done; item 1 merged to main as `cf67a46`, not yet on this branch. Item 2 is refiled as `2026-10-12-mobile-stalled-get-receive-timeout.md` (open).
- `~/Code/claude-skills/issues/2026-10-07-mobile-interceptor-retry-crosses-session-change.md` is done: the stale-token fix is on main `cf67a46`.
- `~/Code/claude-skills/issues/2026-10-12-mobile-interceptor-session-ownership.md` is open. The retry and 401-refresh interceptors re-send a request under whichever session is current, not the one that started it.
